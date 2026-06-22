// lib/core/executor.dart
// 8086 machine code executor — runs binary bytes directly from CPU memory.
// Used by the DEBUG 'G' (go) and 'T' (trace) commands.

import 'cpu8086.dart';

class ExecResult {
  final bool halted;
  final String? error;
  final int steps;
  ExecResult({this.halted = false, this.error, this.steps = 0});
}

class Executor {
  final CPU8086 cpu;
  static const int maxSteps = 500000;

  Executor(this.cpu);

  // Execute one instruction (trace / single-step)
  ExecResult stepOne() {
    if (cpu.halted) return ExecResult(halted: true);
    try {
      final stepped = _executeOne();
      return ExecResult(halted: cpu.halted, steps: stepped ? 1 : 0);
    } catch (e) {
      cpu.halted = true;
      return ExecResult(halted: true, error: e.toString());
    }
  }

  // Run until HLT, INT 20h, or INT 21h AH=4C, or breakpoint, or maxSteps
  ExecResult run({int? breakAt}) {
    int steps = 0;
    while (!cpu.halted && steps < maxSteps) {
      if (breakAt != null && cpu.ip == breakAt && steps > 0) break;
      try {
        _executeOne();
      } catch (e) {
        cpu.halted = true;
        return ExecResult(halted: true, error: e.toString(), steps: steps);
      }
      steps++;
    }
    return ExecResult(halted: cpu.halted, steps: steps);
  }

  bool _executeOne() {
    int fetch() {
      final b = cpu.memory[cpu.ip & 0xFFFF];
      cpu.ip = (cpu.ip + 1) & 0xFFFF;
      return b;
    }
    int fetch16() {
      final lo = fetch(); final hi = fetch();
      return lo | (hi << 8);
    }
    int signExt8(int b) => b > 127 ? b - 256 : b;
    int signExt16(int w) => w > 32767 ? w - 65536 : w;

    // ModRM decode: returns getter/setter pair
    // Returns a _Operand holding value and a way to write back
    _Operand decodeRM(int modrm, bool is16) {
      final mod = (modrm >> 6) & 3;
      final rm  = modrm & 7;

      int calcAddr() {
        switch (rm) {
          case 0: return (cpu.bx + cpu.si) & 0xFFFF;
          case 1: return (cpu.bx + cpu.di) & 0xFFFF;
          case 2: return (cpu.bp + cpu.si) & 0xFFFF;
          case 3: return (cpu.bp + cpu.di) & 0xFFFF;
          case 4: return cpu.si;
          case 5: return cpu.di;
          case 6: return cpu.bp;
          case 7: return cpu.bx;
          default: return 0;
        }
      }

      if (mod == 3) {
        // register
        if (is16) {
          return _Operand(
            get: () => _getReg16(rm),
            set: (v) => _setReg16(rm, v),
            is16: true,
          );
        } else {
          return _Operand(
            get: () => _getReg8(rm),
            set: (v) => _setReg8(rm, v),
            is16: false,
          );
        }
      }

      int addr;
      if (mod == 0 && rm == 6) {
        addr = fetch16();
      } else {
        addr = calcAddr();
        if (mod == 1) {
          addr = (addr + signExt8(fetch())) & 0xFFFF;
        } else if (mod == 2) {
          addr = (addr + signExt16(fetch16())) & 0xFFFF;
        }
      }

      if (is16) {
        return _Operand(
          get: () => cpu.readWord(addr),
          set: (v) => cpu.writeWord(addr, v),
          is16: true,
        );
      } else {
        return _Operand(
          get: () => cpu.readByte(addr),
          set: (v) => cpu.writeByte(addr, v),
          is16: false,
        );
      }
    }

    _Operand decodeReg(int modrm, bool is16) {
      final reg = (modrm >> 3) & 7;
      if (is16) {
        return _Operand(get: () => _getReg16(reg), set: (v) => _setReg16(reg, v), is16: true);
      } else {
        return _Operand(get: () => _getReg8(reg), set: (v) => _setReg8(reg, v), is16: false);
      }
    }

    // ── ALU helpers ──────────────────────────────────────────────────────
    void aluOp(String op, _Operand dst, int src, bool is16) {
      final a = dst.get();
      int result;
      switch (op) {
        case 'ADD': result = a + src; break;
        case 'OR':  result = a | src; break;
        case 'ADC': result = a + src + (cpu.cf ? 1 : 0); break;
        case 'SBB': result = a - src - (cpu.cf ? 1 : 0); break;
        case 'AND': result = a & src; cpu.cf = false; cpu.of_ = false; break;
        case 'SUB': result = a - src; break;
        case 'XOR': result = a ^ src; cpu.cf = false; cpu.of_ = false; break;
        case 'CMP': result = a - src; break; // don't write back
        default: result = a;
      }
      if (is16) cpu.updateFlags16(result); else cpu.updateFlags8(result);
      if (op != 'CMP') dst.set(result & (is16 ? 0xFFFF : 0xFF));
    }

    const aluOps = ['ADD','OR','ADC','SBB','AND','SUB','XOR','CMP'];

    final opcode = fetch();

    switch (opcode) {
      // ── NOP ─────────────────────────────────────────────────────────────
      case 0x90: break;

      // ── HLT ─────────────────────────────────────────────────────────────
      case 0xF4: cpu.halted = true; break;

      // ── MOV r/m, r ──────────────────────────────────────────────────────
      case 0x88: case 0x89: case 0x8A: case 0x8B: {
        final is16 = (opcode & 1) == 1;
        final dir  = (opcode & 2) == 2;
        final b2   = fetch();
        final rm   = decodeRM(b2, is16);
        final reg  = decodeReg(b2, is16);
        if (dir) reg.set(rm.get()); else rm.set(reg.get());
        break;
      }
      // MOV Sreg
      case 0x8C: { final b2=fetch(); _setSeg((b2>>3)&3, decodeRM(b2,true).get()); break; }
      case 0x8E: { final b2=fetch(); decodeRM(b2,true).set(_getSeg((b2>>3)&3)); break; }
      // MOV r, imm
      case 0xB0:case 0xB1:case 0xB2:case 0xB3:case 0xB4:case 0xB5:case 0xB6:case 0xB7:
        _setReg8(opcode & 7, fetch()); break;
      case 0xB8:case 0xB9:case 0xBA:case 0xBB:case 0xBC:case 0xBD:case 0xBE:case 0xBF:
        _setReg16(opcode & 7, fetch16()); break;
      // MOV accum-mem
      case 0xA0: cpu.al = cpu.readByte(fetch16()); break;
      case 0xA1: cpu.ax = cpu.readWord(fetch16()); break;
      case 0xA2: cpu.writeByte(fetch16(), cpu.al); break;
      case 0xA3: cpu.writeWord(fetch16(), cpu.ax); break;
      // MOV r/m, imm
      case 0xC6: { final b2=fetch(); decodeRM(b2,false).set(fetch()); break; }
      case 0xC7: { final b2=fetch(); decodeRM(b2,true).set(fetch16()); break; }

      // ── XCHG ────────────────────────────────────────────────────────────
      case 0x86: { final b2=fetch(); final rm=decodeRM(b2,false); final rg=decodeReg(b2,false); final t=rm.get(); rm.set(rg.get()); rg.set(t); break; }
      case 0x87: { final b2=fetch(); final rm=decodeRM(b2,true);  final rg=decodeReg(b2,true);  final t=rm.get(); rm.set(rg.get()); rg.set(t); break; }
      case 0x91:case 0x92:case 0x93:case 0x94:case 0x95:case 0x96:case 0x97: {
        final t=cpu.ax; cpu.ax=_getReg16(opcode&7); _setReg16(opcode&7,t); break;
      }

      // ── ALU reg/mem patterns ─────────────────────────────────────────────
      case 0x00:case 0x01:case 0x02:case 0x03:
      case 0x08:case 0x09:case 0x0A:case 0x0B:
      case 0x10:case 0x11:case 0x12:case 0x13:
      case 0x18:case 0x19:case 0x1A:case 0x1B:
      case 0x20:case 0x21:case 0x22:case 0x23:
      case 0x28:case 0x29:case 0x2A:case 0x2B:
      case 0x30:case 0x31:case 0x32:case 0x33:
      case 0x38:case 0x39:case 0x3A:case 0x3B: {
        final grp  = (opcode >> 3) & 7; // 0..7 maps to ADD..CMP
        final is16 = (opcode & 1) == 1;
        final dir  = (opcode & 2) == 2;
        final b2   = fetch();
        final rm   = decodeRM(b2, is16);
        final reg  = decodeReg(b2, is16);
        if (dir) aluOp(aluOps[grp], reg, rm.get(), is16);
        else     aluOp(aluOps[grp], rm,  reg.get(), is16);
        break;
      }
      // ALU accum-imm
      case 0x04: aluOp('ADD',_Operand.al(cpu), fetch(), false); break;
      case 0x05: aluOp('ADD',_Operand.ax(cpu), fetch16(), true); break;
      case 0x0C: aluOp('OR', _Operand.al(cpu), fetch(), false); break;
      case 0x0D: aluOp('OR', _Operand.ax(cpu), fetch16(), true); break;
      case 0x14: aluOp('ADC',_Operand.al(cpu), fetch(), false); break;
      case 0x15: aluOp('ADC',_Operand.ax(cpu), fetch16(), true); break;
      case 0x1C: aluOp('SBB',_Operand.al(cpu), fetch(), false); break;
      case 0x1D: aluOp('SBB',_Operand.ax(cpu), fetch16(), true); break;
      case 0x24: aluOp('AND',_Operand.al(cpu), fetch(), false); break;
      case 0x25: aluOp('AND',_Operand.ax(cpu), fetch16(), true); break;
      case 0x2C: aluOp('SUB',_Operand.al(cpu), fetch(), false); break;
      case 0x2D: aluOp('SUB',_Operand.ax(cpu), fetch16(), true); break;
      case 0x34: aluOp('XOR',_Operand.al(cpu), fetch(), false); break;
      case 0x35: aluOp('XOR',_Operand.ax(cpu), fetch16(), true); break;
      case 0x3C: aluOp('CMP',_Operand.al(cpu), fetch(), false); break;
      case 0x3D: aluOp('CMP',_Operand.ax(cpu), fetch16(), true); break;

      // ── GRP1: 80/81/83 ──────────────────────────────────────────────────
      case 0x80: { final b2=fetch(); final rm=decodeRM(b2,false); aluOp(aluOps[(b2>>3)&7], rm, fetch(), false); break; }
      case 0x81: { final b2=fetch(); final rm=decodeRM(b2,true);  aluOp(aluOps[(b2>>3)&7], rm, fetch16(), true); break; }
      case 0x83: { final b2=fetch(); final rm=decodeRM(b2,true);  aluOp(aluOps[(b2>>3)&7], rm, signExt8(fetch()), true); break; }

      // ── INC / DEC ────────────────────────────────────────────────────────
      case 0x40:case 0x41:case 0x42:case 0x43:case 0x44:case 0x45:case 0x46:case 0x47: {
        final r=opcode&7; final v=(_getReg16(r)+1)&0xFFFF; _setReg16(r,v);
        cpu.updateFlags16(v); cpu.cf=cpu.cf; // INC doesn't change CF
        break;
      }
      case 0x48:case 0x49:case 0x4A:case 0x4B:case 0x4C:case 0x4D:case 0x4E:case 0x4F: {
        final r=opcode&7; final v=(_getReg16(r)-1)&0xFFFF; _setReg16(r,v);
        cpu.updateFlags16(v);
        break;
      }

      // ── PUSH / POP ────────────────────────────────────────────────────────
      case 0x50:case 0x51:case 0x52:case 0x53:case 0x54:case 0x55:case 0x56:case 0x57:
        cpu.pushWord(_getReg16(opcode&7)); break;
      case 0x58:case 0x59:case 0x5A:case 0x5B:case 0x5C:case 0x5D:case 0x5E:case 0x5F:
        _setReg16(opcode&7, cpu.popWord()); break;
      case 0x06: cpu.pushWord(cpu.es); break;
      case 0x0E: cpu.pushWord(cpu.cs); break;
      case 0x16: cpu.pushWord(cpu.ss); break;
      case 0x1E: cpu.pushWord(cpu.ds); break;
      case 0x07: cpu.es = cpu.popWord(); break;
      case 0x17: cpu.ss = cpu.popWord(); break;
      case 0x1F: cpu.ds = cpu.popWord(); break;
      case 0x68: cpu.pushWord(fetch16()); break;
      case 0x6A: cpu.pushWord(signExt8(fetch())); break;
      case 0x8F: { final b2=fetch(); final rm=decodeRM(b2,true); rm.set(cpu.popWord()); break; }
      case 0x60: { // PUSHA
        final sp=cpu.sp;
        for (final r in [0,1,2,3,4,5,6,7]) {
          cpu.pushWord(r==4 ? sp : _getReg16(r));
        }
        break;
      }
      case 0x61: { // POPA
        for (final r in [7,6,5,4,3,2,1,0]) {
          final v=cpu.popWord();
          if (r!=4) _setReg16(r,v);
        }
        break;
      }
      case 0x9C: cpu.pushWord(cpu.flagsWord); break;
      case 0x9D: cpu.flagsWord = cpu.popWord(); break;

      // ── MUL / IMUL / DIV / IDIV / NEG / NOT / TEST ────────────────────
      case 0xF6: {
        final b2=fetch(); final rm=decodeRM(b2,false); final ext=(b2>>3)&7;
        switch(ext){
          case 0: case 1: { final r=rm.get()&fetch(); cpu.updateFlags8(r); cpu.cf=false; cpu.of_=false; break; }
          case 2: rm.set((~rm.get())&0xFF); break;
          case 3: { final v=(-(rm.get())).toSigned(8)&0xFF; rm.set(v); cpu.updateFlags8(v); break; }
          case 4: { final v=cpu.al*rm.get(); cpu.ax=v&0xFFFF; cpu.cf=cpu.of_=(v>>8)!=0; break; }
          case 5: { final v=cpu.al.toSigned(8)*rm.get().toSigned(8); cpu.ax=v&0xFFFF; break; }
          case 6: { if(rm.get()==0) throw Exception('Division by zero'); cpu.al=(cpu.ax~/rm.get())&0xFF; cpu.ah=(cpu.ax%rm.get())&0xFF; break; }
          case 7: { if(rm.get()==0) throw Exception('Division by zero'); final d=cpu.ax.toSigned(16)~/rm.get().toSigned(8); cpu.al=d&0xFF; cpu.ah=(cpu.ax.toSigned(16)%rm.get().toSigned(8))&0xFF; break; }
        }
        break;
      }
      case 0xF7: {
        final b2=fetch(); final rm=decodeRM(b2,true); final ext=(b2>>3)&7;
        switch(ext){
          case 0: case 1: { final r=cpu.ax&fetch16(); cpu.updateFlags16(r); cpu.cf=false; cpu.of_=false; break; }
          case 2: rm.set((~rm.get())&0xFFFF); break;
          case 3: { final v=(-(rm.get()))&0xFFFF; rm.set(v); cpu.updateFlags16(v); break; }
          case 4: { final v=cpu.ax*rm.get(); cpu.ax=v&0xFFFF; cpu.dx=(v>>16)&0xFFFF; cpu.cf=cpu.of_=cpu.dx!=0; break; }
          case 6: { if(rm.get()==0) throw Exception('Division by zero'); final d=((cpu.dx<<16)|cpu.ax)~/rm.get(); cpu.ax=d&0xFFFF; cpu.dx=((cpu.dx<<16)|cpu.ax)%rm.get()&0xFFFF; break; }
          default: break;
        }
        break;
      }

      // ── TEST ────────────────────────────────────────────────────────────
      case 0x84: { final b2=fetch(); final r=(decodeRM(b2,false).get()&decodeReg(b2,false).get())&0xFF; cpu.updateFlags8(r); cpu.cf=false; cpu.of_=false; break; }
      case 0x85: { final b2=fetch(); final r=(decodeRM(b2,true).get()&decodeReg(b2,true).get())&0xFFFF; cpu.updateFlags16(r); cpu.cf=false; cpu.of_=false; break; }
      case 0xA8: { final r=(cpu.al&fetch())&0xFF; cpu.updateFlags8(r); cpu.cf=false; cpu.of_=false; break; }
      case 0xA9: { final r=(cpu.ax&fetch16())&0xFFFF; cpu.updateFlags16(r); cpu.cf=false; cpu.of_=false; break; }

      // ── FE: INC/DEC r/m8 ────────────────────────────────────────────────
      case 0xFE: {
        final b2=fetch(); final rm=decodeRM(b2,false); final ext=(b2>>3)&7;
        if(ext==0){ final v=(rm.get()+1)&0xFF; rm.set(v); cpu.updateFlags8(v); }
        else if(ext==1){ final v=(rm.get()-1)&0xFF; rm.set(v); cpu.updateFlags8(v); }
        break;
      }
      // ── FF: INC/DEC/CALL/JMP/PUSH r/m16 ────────────────────────────────
      case 0xFF: {
        final b2=fetch(); final rm=decodeRM(b2,true); final ext=(b2>>3)&7;
        switch(ext){
          case 0: { final v=(rm.get()+1)&0xFFFF; rm.set(v); cpu.updateFlags16(v); break; }
          case 1: { final v=(rm.get()-1)&0xFFFF; rm.set(v); cpu.updateFlags16(v); break; }
          case 2: cpu.pushWord(cpu.ip); cpu.ip=rm.get(); break;
          case 4: cpu.ip=rm.get(); break;
          case 6: cpu.pushWord(rm.get()); break;
        }
        break;
      }

      // ── Jumps ────────────────────────────────────────────────────────────
      case 0x70: { final rel=signExt8(fetch()); if(cpu.of_)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x71: { final rel=signExt8(fetch()); if(!cpu.of_) cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x72: { final rel=signExt8(fetch()); if(cpu.cf)   cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x73: { final rel=signExt8(fetch()); if(!cpu.cf)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x74: { final rel=signExt8(fetch()); if(cpu.zf)   cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x75: { final rel=signExt8(fetch()); if(!cpu.zf)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x76: { final rel=signExt8(fetch()); if(cpu.cf||cpu.zf)   cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x77: { final rel=signExt8(fetch()); if(!cpu.cf&&!cpu.zf) cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x78: { final rel=signExt8(fetch()); if(cpu.sf)   cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x79: { final rel=signExt8(fetch()); if(!cpu.sf)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7A: { final rel=signExt8(fetch()); if(cpu.pf)   cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7B: { final rel=signExt8(fetch()); if(!cpu.pf)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7C: { final rel=signExt8(fetch()); if(cpu.sf!=cpu.of_)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7D: { final rel=signExt8(fetch()); if(cpu.sf==cpu.of_)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7E: { final rel=signExt8(fetch()); if(cpu.zf||(cpu.sf!=cpu.of_))  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0x7F: { final rel=signExt8(fetch()); if(!cpu.zf&&(cpu.sf==cpu.of_)) cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xEB: { final rel=signExt8(fetch()); cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xE9: { final rel=signExt16(fetch16()); cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xEA: { final off=fetch16(); final seg=fetch16(); cpu.cs=seg; cpu.ip=off; break; }

      // ── LOOP ─────────────────────────────────────────────────────────────
      case 0xE0: { final rel=signExt8(fetch()); cpu.cx=(cpu.cx-1)&0xFFFF; if(cpu.cx!=0&&!cpu.zf) cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xE1: { final rel=signExt8(fetch()); cpu.cx=(cpu.cx-1)&0xFFFF; if(cpu.cx!=0&&cpu.zf)  cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xE2: { final rel=signExt8(fetch()); cpu.cx=(cpu.cx-1)&0xFFFF; if(cpu.cx!=0)          cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xE3: { final rel=signExt8(fetch()); if(cpu.cx==0) cpu.ip=(cpu.ip+rel)&0xFFFF; break; }

      // ── CALL / RET ────────────────────────────────────────────────────────
      case 0xE8: { final rel=signExt16(fetch16()); cpu.pushWord(cpu.ip); cpu.ip=(cpu.ip+rel)&0xFFFF; break; }
      case 0xC3: cpu.ip = cpu.popWord(); break;
      case 0xC2: { final n=fetch16(); cpu.ip=cpu.popWord(); cpu.sp=(cpu.sp+n)&0xFFFF; break; }
      case 0xCB: { cpu.ip=cpu.popWord(); cpu.cs=cpu.popWord(); break; }

      // ── INT ──────────────────────────────────────────────────────────────
      case 0xCD: { final n=fetch(); _handleInt(n); break; }
      case 0xCC: _handleInt(3); break;
      case 0xCF: { cpu.ip=cpu.popWord(); cpu.cs=cpu.popWord(); cpu.flagsWord=cpu.popWord(); break; }

      // ── LEA ──────────────────────────────────────────────────────────────
      case 0x8D: {
        final b2=fetch();
        final mod=(b2>>6)&3; final rm2=b2&7; final reg2=(b2>>3)&7;
        // Compute EA without reading memory
        int ea;
        switch(rm2){
          case 0: ea=(cpu.bx+cpu.si)&0xFFFF; break;
          case 1: ea=(cpu.bx+cpu.di)&0xFFFF; break;
          case 2: ea=(cpu.bp+cpu.si)&0xFFFF; break;
          case 3: ea=(cpu.bp+cpu.di)&0xFFFF; break;
          case 4: ea=cpu.si; break;
          case 5: ea=cpu.di; break;
          case 6: if(mod==0){ea=fetch16();}else{ea=cpu.bp;}break;
          case 7: ea=cpu.bx; break;
          default: ea=0;
        }
        if(mod==1) ea=(ea+signExt8(fetch()))&0xFFFF;
        else if(mod==2) ea=(ea+signExt16(fetch16()))&0xFFFF;
        _setReg16(reg2, ea);
        break;
      }

      // ── CBW / CWD ────────────────────────────────────────────────────────
      case 0x98: cpu.ax = cpu.al > 127 ? (0xFF00 | cpu.al) : cpu.al; break;
      case 0x99: cpu.dx = cpu.ax > 32767 ? 0xFFFF : 0; break;

      // ── String ops ────────────────────────────────────────────────────────
      case 0xA4: cpu.writeByte(cpu.di, cpu.readByte(cpu.si)); cpu.si=(cpu.si+(cpu.df?-1:1))&0xFFFF; cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break;
      case 0xA5: cpu.writeWord(cpu.di, cpu.readWord(cpu.si)); cpu.si=(cpu.si+(cpu.df?-2:2))&0xFFFF; cpu.di=(cpu.di+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAA: cpu.writeByte(cpu.di, cpu.al); cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break;
      case 0xAB: cpu.writeWord(cpu.di, cpu.ax); cpu.di=(cpu.di+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAC: cpu.al=cpu.readByte(cpu.si); cpu.si=(cpu.si+(cpu.df?-1:1))&0xFFFF; break;
      case 0xAD: cpu.ax=cpu.readWord(cpu.si); cpu.si=(cpu.si+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAE: { final r=(cpu.al-cpu.readByte(cpu.di))&0xFF; cpu.updateFlags8(r); cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break; }

      // ── REP prefix ────────────────────────────────────────────────────────
      case 0xF3: {
        final next=fetch();
        while(cpu.cx!=0){
          _executeStringOp(next);
          cpu.cx=(cpu.cx-1)&0xFFFF;
          if(next==0xA6||next==0xA7||next==0xAE||next==0xAF){
            if(!cpu.zf) break;
          }
        }
        break;
      }
      case 0xF2: {
        final next=fetch();
        while(cpu.cx!=0){
          _executeStringOp(next);
          cpu.cx=(cpu.cx-1)&0xFFFF;
          if(cpu.zf) break;
        }
        break;
      }

      // ── Flag ops ──────────────────────────────────────────────────────────
      case 0xF8: cpu.cf=false; break;
      case 0xF9: cpu.cf=true; break;
      case 0xFA: cpu.ifl=false; break;
      case 0xFB: cpu.ifl=true; break;
      case 0xFC: cpu.df=false; break;
      case 0xFD: cpu.df=true; break;
      case 0x9E: { final f=cpu.flagsWord; cpu.ah=f&0xFF; break; }
      case 0x9F: { cpu.flagsWord=(cpu.flagsWord&0xFF00)|cpu.ah; break; }

      // ── Segment overrides (simplified: ignore prefix, exec next) ──────────
      case 0x26: case 0x2E: case 0x36: case 0x3E: _executeOne(); break;

      // ── GRP2: shifts ─────────────────────────────────────────────────────
      case 0xD0: case 0xD1: case 0xD2: case 0xD3: {
        final is16=(opcode&1)==1; final useCL=(opcode&2)==2;
        final b2=fetch(); final rm=decodeRM(b2,is16); final ext=(b2>>3)&7;
        final count = useCL ? cpu.cl : 1;
        var v = rm.get();
        for(int i=0;i<count;i++){
          switch(ext){
            case 0: { final c=(v>>(is16?15:7))&1; v=(v<<1)|(cpu.cf?1:0); cpu.cf=c!=0; break; } // RCL simplified as ROL
            case 1: { final c=v&1; v=(v>>(is16?0:0)); v=is16?(v>>1)|((cpu.cf?1:0)<<15):(v>>1)|((cpu.cf?1:0)<<7); cpu.cf=c!=0; break; } // RCR
            case 4: case 6: { cpu.cf=(v>>(is16?15:7))&1!=0; v=(v<<1)&(is16?0xFFFF:0xFF); break; } // SHL
            case 5: { cpu.cf=(v&1)!=0; v=v>>(1); break; } // SHR logical
            case 7: { cpu.cf=(v&1)!=0; v=is16?(v.toSigned(16)>>1)&0xFFFF:(v.toSigned(8)>>1)&0xFF; break; } // SAR
          }
        }
        rm.set(v&(is16?0xFFFF:0xFF));
        if(is16) cpu.updateFlags16(v); else cpu.updateFlags8(v);
        break;
      }

      // ── XLAT ────────────────────────────────────────────────────────────
      case 0xD7: cpu.al = cpu.readByte((cpu.bx + cpu.al) & 0xFFFF); break;

      // ── IN / OUT ────────────────────────────────────────────────────────
      case 0xE4: fetch(); cpu.al=0; break; // IN — returns 0
      case 0xE5: fetch(); cpu.ax=0; break;
      case 0xE6: fetch(); break; // OUT — no-op
      case 0xE7: fetch(); break;
      case 0xEC: cpu.al=0; break;
      case 0xED: cpu.ax=0; break;
      case 0xEE: case 0xEF: break;

      // ── DAA/DAS/AAA/AAS/AAM/AAD ──────────────────────────────────────────
      case 0x27: { // DAA
        if((cpu.al&0xF)>9||cpu.af){ cpu.al=(cpu.al+6)&0xFF; cpu.af=true; } else cpu.af=false;
        if(cpu.al>0x9F||cpu.cf){ cpu.al=(cpu.al+0x60)&0xFF; cpu.cf=true; } else cpu.cf=false;
        cpu.updateFlags8(cpu.al); break;
      }
      case 0xD4: fetch(); { final t=cpu.al~/10; cpu.ah=t; cpu.al=cpu.al%10; cpu.updateFlags8(cpu.al); break; } // AAM
      case 0xD5: fetch(); { cpu.al=(cpu.ah*10+cpu.al)&0xFF; cpu.ah=0; cpu.updateFlags8(cpu.al); break; } // AAD
      case 0x37: { if((cpu.al&0xF)>9||cpu.af){ cpu.al=(cpu.al+6)&0xFF; cpu.ah=(cpu.ah+1)&0xFF; cpu.cf=cpu.af=true; } else{cpu.cf=cpu.af=false;} cpu.al&=0x0F; break; } // AAA
      case 0x2F: break; // DAS simplified
      case 0x3F: break; // AAS simplified

      // ── ENTER / LEAVE ────────────────────────────────────────────────────
      case 0xC8: { final sz=fetch16(); fetch(); cpu.pushWord(cpu.bp); cpu.bp=cpu.sp; cpu.sp=(cpu.sp-sz)&0xFFFF; break; }
      case 0xC9: { cpu.sp=cpu.bp; cpu.bp=cpu.popWord(); break; }

      default:
        // Unknown opcode — just skip (like real DEBUG showing DB)
        break;
    }
    return true;
  }

  void _executeStringOp(int op) {
    switch(op){
      case 0xA4: cpu.writeByte(cpu.di, cpu.readByte(cpu.si)); cpu.si=(cpu.si+(cpu.df?-1:1))&0xFFFF; cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break;
      case 0xA5: cpu.writeWord(cpu.di, cpu.readWord(cpu.si)); cpu.si=(cpu.si+(cpu.df?-2:2))&0xFFFF; cpu.di=(cpu.di+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAA: cpu.writeByte(cpu.di, cpu.al); cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break;
      case 0xAB: cpu.writeWord(cpu.di, cpu.ax); cpu.di=(cpu.di+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAC: cpu.al=cpu.readByte(cpu.si); cpu.si=(cpu.si+(cpu.df?-1:1))&0xFFFF; break;
      case 0xAD: cpu.ax=cpu.readWord(cpu.si); cpu.si=(cpu.si+(cpu.df?-2:2))&0xFFFF; break;
      case 0xAE: { final r=(cpu.al-cpu.readByte(cpu.di))&0xFF; cpu.updateFlags8(r); cpu.di=(cpu.di+(cpu.df?-1:1))&0xFFFF; break; }
    }
  }

  void _handleInt(int n) {
    if (n == 0x20) { cpu.halted = true; return; }
    if (n == 0x21) {
      switch (cpu.ah) {
        case 0x02:
          cpu.outputLog.add(String.fromCharCode(cpu.dl));
          break;
        case 0x09: {
          int addr = cpu.dx;
          final sb = StringBuffer();
          while (addr < 65536) {
            final ch = cpu.memory[addr++];
            if (ch == 0x24) break;
            sb.writeCharCode(ch);
          }
          cpu.outputLog.add(sb.toString());
          break;
        }
        case 0x4C: cpu.halted = true; break;
        case 0x01: cpu.al = 0x0D; break; // Read char — return CR
        case 0x0A: break; // Buffered input — no-op
        default:
          cpu.outputLog.add('[INT 21h AH=${cpu.ah.toRadixString(16).toUpperCase().padLeft(2,'0')}h]');
      }
    } else if (n == 0x10) {
      if (cpu.ah == 0x0E) cpu.outputLog.add(String.fromCharCode(cpu.al));
    } else {
      cpu.outputLog.add('[INT ${n.toRadixString(16).toUpperCase().padLeft(2,'0')}h]');
    }
  }

  // Register helpers by index (ModRM encoding order)
  int _getReg16(int r) {
    switch(r){case 0:return cpu.ax;case 1:return cpu.cx;case 2:return cpu.dx;case 3:return cpu.bx;case 4:return cpu.sp;case 5:return cpu.bp;case 6:return cpu.si;case 7:return cpu.di;default:return 0;}
  }
  void _setReg16(int r, int v){v&=0xFFFF;switch(r){case 0:cpu.ax=v;break;case 1:cpu.cx=v;break;case 2:cpu.dx=v;break;case 3:cpu.bx=v;break;case 4:cpu.sp=v;break;case 5:cpu.bp=v;break;case 6:cpu.si=v;break;case 7:cpu.di=v;break;}}
  int _getReg8(int r){switch(r){case 0:return cpu.al;case 1:return cpu.cl;case 2:return cpu.dl;case 3:return cpu.bl;case 4:return cpu.ah;case 5:return cpu.ch;case 6:return cpu.dh;case 7:return cpu.bh;default:return 0;}}
  void _setReg8(int r, int v){v&=0xFF;switch(r){case 0:cpu.al=v;break;case 1:cpu.cl=v;break;case 2:cpu.dl=v;break;case 3:cpu.bl=v;break;case 4:cpu.ah=v;break;case 5:cpu.ch=v;break;case 6:cpu.dh=v;break;case 7:cpu.bh=v;break;}}
  int _getSeg(int r){switch(r){case 0:return cpu.es;case 1:return cpu.cs;case 2:return cpu.ss;case 3:return cpu.ds;default:return 0;}}
  void _setSeg(int r, int v){v&=0xFFFF;switch(r){case 0:cpu.es=v;break;case 1:cpu.cs=v;break;case 2:cpu.ss=v;break;case 3:cpu.ds=v;break;}}
}

// Small helper: wraps a register or memory cell with get/set
class _Operand {
  final int Function() get;
  final void Function(int) set;
  final bool is16;

  _Operand({required this.get, required this.set, required this.is16});

  static _Operand al(CPU8086 cpu) => _Operand(get: () => cpu.al, set: (v) => cpu.al = v & 0xFF, is16: false);
  static _Operand ax(CPU8086 cpu) => _Operand(get: () => cpu.ax, set: (v) => cpu.ax = v & 0xFFFF, is16: true);
}

extension _ToSigned on int {
  int toSigned(int bits) {
    final sign = 1 << (bits - 1);
    final mask = (sign << 1) - 1;
    final v = this & mask;
    return v >= sign ? v - (sign << 1) : v;
  }
}
