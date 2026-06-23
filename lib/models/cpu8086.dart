// lib/models/cpu8086.dart
// 8086 CPU State: registers, flags, memory, stack

class CPU8086 {
  // General purpose registers (16-bit)
  int ax = 0, bx = 0, cx = 0, dx = 0;
  // Index registers
  int si = 0, di = 0;
  // Pointer registers
  int sp = 0xFFFE, bp = 0;
  // Segment registers
  int cs = 0, ds = 0, ss = 0, es = 0;
  // Instruction pointer
  int ip = 0x0100;

  // Flags
  bool zf = false; // Zero flag
  bool sf = false; // Sign flag
  bool cf = false; // Carry flag
  bool of = false; // Overflow flag
  bool pf = false; // Parity flag

  // Memory: 64KB
  final List<int> memory = List.filled(65536, 0);

  // Execution output log
  final List<String> outputLog = [];
  bool halted = false;

  // High/Low byte accessors
  int get ah => (ax >> 8) & 0xFF;
  int get al => ax & 0xFF;
  int get bh => (bx >> 8) & 0xFF;
  int get bl => bx & 0xFF;
  int get ch => (cx >> 8) & 0xFF;
  int get cl => cx & 0xFF;
  int get dh => (dx >> 8) & 0xFF;
  int get dl => dx & 0xFF;

  set ah(int v) => ax = (ax & 0x00FF) | ((v & 0xFF) << 8);
  set al(int v) => ax = (ax & 0xFF00) | (v & 0xFF);
  set bh(int v) => bx = (bx & 0x00FF) | ((v & 0xFF) << 8);
  set bl(int v) => bx = (bx & 0xFF00) | (v & 0xFF);
  set ch(int v) => cx = (cx & 0x00FF) | ((v & 0xFF) << 8);
  set cl(int v) => cx = (cx & 0xFF00) | (v & 0xFF);
  set dh(int v) => dx = (dx & 0x00FF) | ((v & 0xFF) << 8);
  set dl(int v) => dx = (dx & 0xFF00) | (v & 0xFF);

  void reset() {
    ax = bx = cx = dx = si = di = bp = 0;
    sp = 0xFFFE;
    cs = ds = ss = es = 0;
    ip = 0x0100;
    zf = sf = cf = of = pf = false;
    memory.fillRange(0, memory.length, 0);
    outputLog.clear();
    halted = false;
  }

  void updateFlags16(int result) {
    final masked = result & 0xFFFF;
    zf = masked == 0;
    sf = (masked & 0x8000) != 0;
    cf = result > 0xFFFF || result < 0;
    of = result > 32767 || result < -32768;
    pf = _parity(masked & 0xFF);
  }

  void updateFlags8(int result) {
    final masked = result & 0xFF;
    zf = masked == 0;
    sf = (masked & 0x80) != 0;
    cf = result > 0xFF || result < 0;
    of = result > 127 || result < -128;
    pf = _parity(masked);
  }

  bool _parity(int v) {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if ((v >> i) & 1 == 1) count++;
    }
    return count % 2 == 0;
  }

  void pushWord(int value) {
    sp = (sp - 2) & 0xFFFF;
    memory[sp] = value & 0xFF;
    memory[sp + 1] = (value >> 8) & 0xFF;
  }

  int popWord() {
    final lo = memory[sp];
    final hi = memory[sp + 1];
    sp = (sp + 2) & 0xFFFF;
    return lo | (hi << 8);
  }

  void writeWord(int addr, int value) {
    memory[addr & 0xFFFF] = value & 0xFF;
    memory[(addr + 1) & 0xFFFF] = (value >> 8) & 0xFF;
  }

  int readWord(int addr) {
    return memory[addr & 0xFFFF] | (memory[(addr + 1) & 0xFFFF] << 8);
  }

  int getRegister(String name) {
    switch (name.toLowerCase()) {
      case 'ax': return ax;
      case 'bx': return bx;
      case 'cx': return cx;
      case 'dx': return dx;
      case 'si': return si;
      case 'di': return di;
      case 'sp': return sp;
      case 'bp': return bp;
      case 'ah': return ah;
      case 'al': return al;
      case 'bh': return bh;
      case 'bl': return bl;
      case 'ch': return ch;
      case 'cl': return cl;
      case 'dh': return dh;
      case 'dl': return dl;
      default: throw ArgumentError('Unknown register: $name');
    }
  }

  void setRegister(String name, int value) {
    switch (name.toLowerCase()) {
      case 'ax': ax = value & 0xFFFF; break;
      case 'bx': bx = value & 0xFFFF; break;
      case 'cx': cx = value & 0xFFFF; break;
      case 'dx': dx = value & 0xFFFF; break;
      case 'si': si = value & 0xFFFF; break;
      case 'di': di = value & 0xFFFF; break;
      case 'sp': sp = value & 0xFFFF; break;
      case 'bp': bp = value & 0xFFFF; break;
      case 'ah': ah = value & 0xFF; break;
      case 'al': al = value & 0xFF; break;
      case 'bh': bh = value & 0xFF; break;
      case 'bl': bl = value & 0xFF; break;
      case 'ch': ch = value & 0xFF; break;
      case 'cl': cl = value & 0xFF; break;
      case 'dh': dh = value & 0xFF; break;
      case 'dl': dl = value & 0xFF; break;
      default: throw ArgumentError('Unknown register: $name');
    }
  }

  bool is8BitReg(String name) {
    return ['ah','al','bh','bl','ch','cl','dh','dl'].contains(name.toLowerCase());
  }

  Map<String, dynamic> snapshot() => {
    'AX': ax, 'BX': bx, 'CX': cx, 'DX': dx,
    'SI': si, 'DI': di, 'SP': sp, 'BP': bp,
    'IP': ip, 'CS': cs, 'DS': ds, 'SS': ss,
    'ZF': zf, 'SF': sf, 'CF': cf, 'OF': of, 'PF': pf,
  };
}
