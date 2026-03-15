import os
import re
import shutil
import subprocess
import shlex
import logging
import random
import string
from string import Template
import sys

import riscof.utils as utils
import riscof.constants as constants
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

class dhrutv(pluginTemplate):
    __model__ = "dhrutv"
    __version__ = "0.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')
        if config is None:
            print("Please enter input file paths in configuration.")
            raise SystemExit(1)
        self.dut_exe = os.path.join(config['PATH'] if 'PATH' in config else "","spike")
        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        self.pluginpath=os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])
        if 'target_run' in config and config['target_run']=='0':
            self.target_run = False
        else:
            self.target_run = True

    def initialise(self, suite, work_dir, archtest_env):
       self.work_dir = work_dir
       self.suite_dir = suite
       self.compile_cmd = 'riscv-none-elf-gcc -march={0} \
         -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g\
         -T '+self.pluginpath+'/env/link.ld\
         -I '+self.pluginpath+'/env/\
         -I ' + archtest_env + ' {1} -o {2} {3}'

    def build(self, isa_yaml, platform_yaml):
      ispec = utils.load_yaml(isa_yaml)['hart0']
      self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')
      self.isa = 'rv' + self.xlen
      if "I" in ispec["ISA"]:
          self.isa += 'i'
      if "M" in ispec["ISA"]:
          self.isa += 'm'
      if "F" in ispec["ISA"]:
          self.isa += 'f'
      if "D" in ispec["ISA"]:
          self.isa += 'd'
      if "C" in ispec["ISA"]:
          self.isa += 'c'
      self.compile_cmd = self.compile_cmd+' -mabi='+('lp64 ' if 64 in ispec['supported_xlen'] else 'ilp32 ')

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
    
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = "make -k -j" + self.num_jobs
    
        pyuvm_makefile = os.path.abspath(os.path.join(self.pluginpath, "..", "..", "pyUVM", "Makefile"))
    
        objcopy = "riscv-none-elf-objcopy"
        objdump = "riscv-none-elf-objdump"
        nm      = "riscv-none-elf-nm"

        for testname in testList:
            testentry = testList[testname]
            test = testentry["test_path"]
            test_dir = testentry["work_dir"]
    
            elf = "my.elf"
            hexfile = "my.hex"
            disfile = "my.dis"
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")
            compile_macros = " -D" + " -D".join(testentry["macros"])
    
            compile_cmd = self.compile_cmd.format(
                testentry["isa"].lower(),
                test,
                elf,
                compile_macros
            )
            
            # 1. Run compilation immediately so we can extract symbols in Python
            logger.info(f"Compiling {testname}")
            utils.shellCommand(compile_cmd).run(cwd=test_dir)
            
            # 2. Extract symbols in Python for logging
            def get_symbol(sym, elf_path):
                cmd = f"{nm} -n {elf_path} | awk '$3==\"{sym}\" {{print \"0x\"$1}}'"
                try:
                    res = subprocess.check_output(cmd, shell=True, cwd=test_dir).decode().strip()
                    return res if res else "NOT_FOUND"
                except:
                    return "ERROR"

            elf_abs = os.path.join(test_dir, elf)
            sig_begin = get_symbol("begin_signature", elf_abs)
            sig_end = get_symbol("end_signature", elf_abs)
            tohost_addr = get_symbol("tohost", elf_abs)
            timeout = 100000

            # Remaining commands for the Makefile
            objcopy_cmd = f"{objcopy} -O verilog {shlex.quote(elf)} {shlex.quote(hexfile)}"
            objdump_cmd = f"{objdump} -D -M numeric,no-aliases {shlex.quote(elf)} > {shlex.quote(disfile)}"

            if self.target_run:
                libpython = "/usr/lib/x86_64-linux-gnu/libpython3.12.so.1.0"
                repo_root = os.path.abspath(os.path.join(self.pluginpath, "..", "..", ".."))
                
                # Log everything going into the exports
                logger.info(f"Setting up simulation environment for {testname}:")
                logger.info(f"  SIG_BEGIN:         {sig_begin}")
                logger.info(f"  SIG_END:           {sig_end}")
                logger.info(f"  TOHOST_ADDR:       {tohost_addr}")
                logger.info(f"  TEST_ELF:          {elf_abs}")
                logger.info(f"  TEST_HEX:          {os.path.join(test_dir, hexfile)}")
                logger.info(f"  CYCLE_TIMEOUT:     {timeout}")
                logger.info(f"  SIGNATURE_FILE:    {sig_file}")
                logger.info(f"  COCOTB_LOG_LEVEL:  INFO")
                logger.info(f"  LIBPYTHON_LOC:     {libpython}")
                logger.info(f"  PYTHONPATH:        {repo_root}/test_bench:$PYTHONPATH")

                simcmd = (
                    f"export SIG_BEGIN={sig_begin}; "
                    f"export SIG_END={sig_end}; "
                    f"export TOHOST_ADDR={tohost_addr}; "
                    f"export TEST_ELF={shlex.quote(elf_abs)}; "
                    f"export TEST_HEX={shlex.quote(os.path.join(test_dir, hexfile))}; "
                    f"export CYCLE_TIMEOUT={timeout}; "
                    f"export SIGNATURE_FILE={shlex.quote(sig_file)}; "
                    f"export COCOTB_LOG_LEVEL=INFO; "
                    f"export LIBPYTHON_LOC={libpython}; "
                    f"export PYTHONPATH={repo_root}/test_bench:$$PYTHONPATH; "
                    f"make -f {shlex.quote(pyuvm_makefile)} SIM=verilator LOG_LEVEL=DEBUG COCOTB_TEST_MODULES=run_test"
                )
            else:
                simcmd = 'echo "NO RUN"'
    
            execute = (
                f"@cd {shlex.quote(test_dir)}; "
                f"{objcopy_cmd}; "
                f"{objdump_cmd}; "
                f"{simcmd};"
            )
            make.add_target(execute)
    
        make.execute_all(self.work_dir)
        if not self.target_run:
            raise SystemExit(0)
