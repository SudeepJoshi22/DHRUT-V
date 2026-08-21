import logging
import os
import yaml
from pathlib import Path
from pyuvm import uvm_sequence_item, uvm_monitor, uvm_analysis_port
import cocotb
from cocotb.triggers import RisingEdge

# Default (fixed, non test-name-qualified) deep-trace file name, written to
# the sim run directory (cwd when cocotb/Verilator runs, e.g. tools/pyUVM).
# Overridable via CPU_DEEP_TRACE_FILE for relocation/disabling.
DEFAULT_DEEP_TRACE_FILE = "cpu_deep_trace.log"

# ───────────────────────────────────────────────
# Dynamic Monitor Item - Fields created from YAML
# ───────────────────────────────────────────────
class CpuMonitorItem(uvm_sequence_item):
    def __init__(self, name="CpuMonitorItem", config=None):
        super().__init__(name)
        self.timestamp = 0.0
        self.config = config
        
        # Dynamically create attributes based on YAML config
        if config:
            for stage_name, stage_config in config['stages'].items():
                for signal in stage_config['signals']:
                    # Initialize all signal attributes
                    setattr(self, signal['signal_path'], None)
            
            # Handle all extraction sections (keys ending in _extraction)
            for key, val in config.items():
                if key.endswith('_extraction') and isinstance(val, dict) and 'fields' in val:
                    for field in val['fields']:
                        setattr(self, field['name'], None)
    
    def __str__(self):
        if not self.config:
            return f"@{self.timestamp:6.1f}ns | No config loaded"
        
        s = f"@{self.timestamp:7.1f}ns \n"
        
        # Iterate through stages defined in config
        display_stages = self.config.get('display_stages', self.config['stages'].keys())
        
        for stage_name in display_stages:
            if stage_name not in self.config['stages']:
                continue
            
            stage_config = self.config['stages'][stage_name]
            stage_label = f"[{stage_config['display_name']}]"
            
            # Build stage output with signals
            stage_signals = []
            
            # Display all signals for this stage
            for signal in stage_config['signals']:
                signal_name = signal['name']
                signal_path = signal['signal_path']
                signal_format = signal['format']
                signal_type = signal['type']
                
                # Get value from item
                value = getattr(self, signal_path, None)
                
                # Format based on type
                if value is None:
                    formatted_value = "---"
                elif signal_type == "bool":
                    formatted_value = signal_format.format(int(value))
                elif signal_type == "int":
                    formatted_value = signal_format.format(value)
                else:
                    formatted_value = str(value)
                
                signal_str = f"{signal_name}={formatted_value}"
                stage_signals.append(signal_str)
            
            # Add stage to output
            if stage_signals:
                s += f" | {stage_label} " + " ".join(stage_signals)
                s += f"\n"

        return s

    def format_deep_trace_line(self, cycle):
        """
        Human-readable, single-line-per-cycle rendering for cpu_deep_trace.log:
        a cycle-number prefix followed by one labeled, aligned field group per
        pipeline stage, e.g.:
          cycle=      42 t=  420.0ns | FETCH: valid=1 PC=0x00000010 instr=0x00500113 stall_IF=0 | DECODE: ...
        """
        if not self.config:
            return f"cycle={cycle:8d} t={self.timestamp:8.1f}ns | No config loaded"

        parts = [f"cycle={cycle:8d} t={self.timestamp:8.1f}ns"]

        display_stages = self.config.get('display_stages', self.config['stages'].keys())

        for stage_name in display_stages:
            if stage_name not in self.config['stages']:
                continue

            stage_config = self.config['stages'][stage_name]

            field_strs = []
            for signal in stage_config['signals']:
                signal_name = signal['name']
                signal_path = signal['signal_path']
                signal_format = signal['format']
                signal_type = signal['type']

                value = getattr(self, signal_path, None)

                if value is None:
                    formatted_value = "--"
                elif signal_type == "bool":
                    formatted_value = signal_format.format(int(value))
                elif signal_type == "int":
                    try:
                        formatted_value = signal_format.format(value)
                    except (TypeError, ValueError):
                        formatted_value = str(value)
                else:
                    formatted_value = str(value)

                field_strs.append(f"{signal_name}={formatted_value}")

            if field_strs:
                parts.append(f"{stage_name}: " + " ".join(field_strs))

        return " | ".join(parts)

# ───────────────────────────────────────────────
# CPU Monitor – Dynamically configured from YAML
# ───────────────────────────────────────────────
class CpuMonitor(uvm_monitor):
    def __init__(self, name, parent, config_path="monitor_config.yaml"):
        super().__init__(name, parent)
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.ap = uvm_analysis_port("ap", self)

        # ── Dedicated deep-trace logger/file, separate from simulation.log ──
        # A distinct logger name (not under "my_cpu_tb") so its records don't
        # also propagate into the root-attached simulation.log FileHandler.
        self.deep_trace_logger = logging.getLogger("cpu_deep_trace." + self.get_name())
        self.deep_trace_logger.setLevel(logging.INFO)
        self.deep_trace_logger.propagate = False
        self._deep_trace_handler = None

        deep_trace_path = os.environ.get("CPU_DEEP_TRACE_FILE", DEFAULT_DEEP_TRACE_FILE)
        if deep_trace_path:
            # Avoid stacking duplicate handlers if the monitor is rebuilt.
            for h in self.deep_trace_logger.handlers[:]:
                self.deep_trace_logger.removeHandler(h)
                h.close()

            self._deep_trace_handler = logging.FileHandler(deep_trace_path, mode='w')
            self._deep_trace_handler.setLevel(logging.INFO)
            self._deep_trace_handler.setFormatter(logging.Formatter('%(message)s'))
            self.deep_trace_logger.addHandler(self._deep_trace_handler)

        self._cycle = 0

        # Load YAML configuration
        self.config = self._load_config(config_path)
        self.logger.info(f"Loaded monitor config with {len(self.config['stages'])} stages")
    
    def _load_config(self, config_path):
        """Load monitor configuration from YAML file"""
        config_file = Path(__file__).parent / config_path
        
        if not config_file.exists():
            self.logger.error(f"Config file not found: {config_file}")
            return {'stages': {}}
        
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
        
        return config
    
    def build_phase(self):
        self.dut = cocotb.top
    
    def _extract_fields(self, raw_val, extraction_config):
        """Extract fields from packed signal based on config"""
        extracted = {}
        for field in extraction_config['fields']:
            field_name = field['name']
            bits = field['bits']
            
            if len(bits) == 2:
                msb, lsb = bits
                if msb == lsb:
                    # Single bit
                    extracted[field_name] = bool(raw_val[msb])
                else:
                    # Multi-bit field
                    # Use cocotb slice if possible or manual shift/mask
                    try:
                        extracted[field_name] = int(raw_val[msb:lsb])
                    except:
                        # Fallback for non-standard objects
                        extracted[field_name] = int(raw_val) >> lsb & ((1 << (msb - lsb + 1)) - 1)
            else:
                self.logger.warning(f"Invalid bit specification for {field_name}: {bits}")
        
        return extracted
    
    def _get_signal_value(self, signal_path):
        """
        Recursively get signal value from DUT using dot notation
        e.g., "alu_if.m_valid" -> self.dut.alu_if.m_valid.value
        """
        parts = signal_path.split('.')
        obj = self.dut
        
        try:
            for part in parts:
                obj = getattr(obj, part)
            
            # Get the value if it's a signal
            if hasattr(obj, 'value'):
                return obj.value
            return obj
        except AttributeError as e:
            self.logger.debug(f"Signal not found: {signal_path}")
            return None
    
    async def run_phase(self):
        # Lazily get DUT only when run_phase starts
        if self.dut is None:
            self.dut = cocotb.top
            if self.dut is None:
                self.logger.critical("Failed to get cocotb.top in run_phase!")
                return
        
        self.logger.info("Monitor now observing DUT successfully!")
        
        # Create monitor item with config
        item = CpuMonitorItem(config=self.config)
        
        while True:
            await RisingEdge(self.dut.clk)
            
            item.timestamp = cocotb.utils.get_sim_time(unit="ns")
            
            # 1. Dynamically sample all regular signals from config
            for stage_name, stage_config in self.config['stages'].items():
                for signal in stage_config['signals']:
                    # Skip signals that come from any extraction section
                    if signal.get('source'):
                        continue
                        
                    signal_path = signal['signal_path']
                    signal_type = signal['type']
                    
                    # Get raw value from DUT
                    raw_value = self._get_signal_value(signal_path)
                    
                    if raw_value is not None:
                        # Convert based on type
                        if signal_type == "bool":
                            value = bool(raw_value)
                        elif signal_type == "int":
                            # Handle cocotb LogicArray
                            if hasattr(raw_value, 'to_unsigned'):
                                value = raw_value.to_unsigned()
                            else:
                                try:
                                    value = int(raw_value)
                                except:
                                    value = 0
                        else:
                            value = raw_value
                        
                        setattr(item, signal_path, value)
            
            # 2. Handle all extraction sections (keys ending in _extraction)
            for key, extraction_config in self.config.items():
                if key.endswith('_extraction') and isinstance(extraction_config, dict) and 'signal_path' in extraction_config:
                    uop_signal_path = extraction_config['signal_path']
                    uop_raw = self._get_signal_value(uop_signal_path)
                    
                    if uop_raw is not None:
                        extracted_fields = self._extract_fields(uop_raw, extraction_config)
                        
                        # Set extracted fields in item
                        for field_name, field_value in extracted_fields.items():
                            setattr(item, field_name, field_value)
            
            # Log the item to the generic simulation.log (will use __str__ method)
            self.logger.info(str(item))

            # Log a single readable line per cycle to the dedicated deep-trace file
            self._cycle += 1
            if self.deep_trace_logger.handlers:
                self.deep_trace_logger.info(item.format_deep_trace_line(self._cycle))

            # Broadcast for scoreboard/coverage
            self.ap.write(item)

    def final_phase(self):
        super().final_phase()
        if self._deep_trace_handler is not None:
            self._deep_trace_handler.flush()
            self._deep_trace_handler.close()
            self.deep_trace_logger.removeHandler(self._deep_trace_handler)
            self._deep_trace_handler = None
