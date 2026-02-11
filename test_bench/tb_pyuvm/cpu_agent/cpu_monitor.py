import logging
import yaml
from pathlib import Path
from pyuvm import uvm_sequence_item, uvm_monitor, uvm_analysis_port
import cocotb
from cocotb.triggers import RisingEdge

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
            
            # Handle UOP extraction fields if defined
            if 'uop_extraction' in config:
                for field in config['uop_extraction']['fields']:
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

# ───────────────────────────────────────────────
# CPU Monitor – Dynamically configured from YAML
# ───────────────────────────────────────────────
class CpuMonitor(uvm_monitor):
    def __init__(self, name, parent, config_path="monitor_config.yaml"):
        super().__init__(name, parent)
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.ap = uvm_analysis_port("ap", self)
        
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
    
    def _extract_uop_fields(self, uop_raw):
        """Extract UOP fields from packed signal based on config"""
        if 'uop_extraction' not in self.config:
            return {}
        
        extracted = {}
        for field in self.config['uop_extraction']['fields']:
            field_name = field['name']
            bits = field['bits']
            
            if len(bits) == 2:
                msb, lsb = bits
                if msb == lsb:
                    # Single bit
                    extracted[field_name] = bool(uop_raw[msb])
                else:
                    # Multi-bit field
                    extracted[field_name] = int(uop_raw[msb:lsb])
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
            self.logger.warning(f"Signal not found: {signal_path} - {e}")
            return None
    
    async def run_phase(self):
        # Lazily get DUT only when run_phase starts
        if self.dut is None:
            self.dut = cocotb.top
            if self.dut is None:
                self.logger.critical("Failed to get cocotb.top in run_phase!")
                return
        
        self.logger.info("Monitor now observing DUT successfully!")
        
        # Debug: print all top-level attributes (only once)
        if not hasattr(self, '_printed_attrs'):
            self.logger.info("Available top-level signals in dut:")
            for attr in dir(self.dut):
                if not attr.startswith('_'):
                    self.logger.info(f"  - {attr}")
            self._printed_attrs = True
        
        # Create monitor item with config
        item = CpuMonitorItem(config=self.config)
        
        while True:
            await RisingEdge(self.dut.clk)
            
            item.timestamp = cocotb.utils.get_sim_time(unit="ns")
            
            # Dynamically sample all signals from config
            for stage_name, stage_config in self.config['stages'].items():
                for signal in stage_config['signals']:
                    signal_path = signal['signal_path']
                    signal_type = signal['type']
                    
                    # Skip signals that come from UOP extraction
                    if signal.get('source') == 'uop_extraction':
                        # These will be populated by the UOP extraction logic below
                        continue
                    
                    # Get raw value from DUT
                    raw_value = self._get_signal_value(signal_path)
                    
                    if raw_value is not None:
                        # Convert based on type
                        if signal_type == "bool":
                            value = bool(raw_value)
                        elif signal_type == "int":
                            # Handle cocotb LogicArray
                            if hasattr(raw_value, 'integer'):
                                value = raw_value.integer
                            else:
                                value = int(raw_value)
                        else:
                            value = raw_value
                        
                        setattr(item, signal_path, value)
            
            # Handle UOP extraction if configured
            if 'uop_extraction' in self.config:
                uop_signal_path = self.config['uop_extraction']['signal_path']
                uop_raw = self._get_signal_value(uop_signal_path)
                
                if uop_raw is not None:
                    extracted_fields = self._extract_uop_fields(uop_raw)
                    
                    # Set extracted fields in item
                    for field_name, field_value in extracted_fields.items():
                        setattr(item, field_name, field_value)
                else:
                    self.logger.debug(f"UOP signal not found: {uop_signal_path}")
            
            # Log the item (will use __str__ method)
            #self.logger.info(str(item))
            
            # Broadcast for scoreboard/coverage
            self.ap.write(item)

