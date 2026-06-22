// lib/core/cpu8086.dart
// 8086 CPU State model: all registers, flags, 1MB memory

class CPU8086 {
  // General-purpose registers (16-bit)
  int ax = 0, bx = 0, cx = 0, dx = 0;
  // Index / pointer registers
  int si = 0, di = 0, sp = 0xFFFE, bp = 0;
  // Segment registers
  int cs = 0x0000, ds = 0x0000, ss = 0x0000, es = 0x0000;
  // Instruction pointer
  int ip = 0x0100;

  // Flags
  bool cf = false; // Carry
  bool pf = false; // Parity
  bool af = false; // Auxiliary carry
  bool zf = false; // Zero
  bool sf = false; // Sign
  bool tf = false; // Trap
  bool ifl = false; // Interrupt enable
  bool df = false; // Direction
  bool of_ = false; // Overflow

  // 1MB memory (we use 64KB segment for simplicity)
  final List<int> memory = List.filled(0x10000, 0);

  bool halted = false;
  final List<String> outputLog = [];

  // ── High/Low byte accessors ──────────────────────────────────────────────
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

  // ── Flags word (8086 format) ─────────────────────────────────────────────
  int get flagsWord {
    int f = 0xF002; // reserved bits always set
    if (cf) f |= 0x0001;
    if (pf) f |= 0x0004;
    if (af) f |= 0x0010;
    if (zf) f |= 0x0040;
    if (sf) f |= 0x0080;
    if (tf) f |= 0x0100;
    if (ifl) f |= 0x0200;
    if (df) f |= 0x0400;
    if (of_) f |= 0x0800;
    return f & 0xFFFF;
  }

  set flagsWord(int f) {
    cf = (f & 0x0001) != 0;
    pf = (f & 0x0004) != 0;
    af = (f & 0x0010) != 0;
    zf = (f & 0x0040) != 0;
    sf = (f & 0x0080) != 0;
    tf = (f & 0x0100) != 0;
    ifl = (f & 0x0200) != 0;
    df = (f & 0x0400) != 0;
    of_ = (f & 0x0800) != 0;
  }

  // ── Flag helpers ─────────────────────────────────────────────────────────
  void updateFlags16(int result, {int? src, int? dst}) {
    final r16 = result & 0xFFFF;
    zf = r16 == 0;
    sf = (r16 & 0x8000) != 0;
    cf = result > 0xFFFF || result < 0;
    pf = _parity(r16 & 0xFF);
    af = false; // simplified
  }

  void updateFlags8(int result, {int? src, int? dst}) {
    final r8 = result & 0xFF;
    zf = r8 == 0;
    sf = (r8 & 0x80) != 0;
    cf = result > 0xFF || result < 0;
    pf = _parity(r8);
    af = false;
  }

  bool _parity(int v) {
    int n = 0;
    for (int i = 0; i < 8; i++) {
      if ((v >> i) & 1 == 1) n++;
    }
    return n % 2 == 0;
  }

  // ── Memory helpers ───────────────────────────────────────────────────────
  int readByte(int addr) => memory[addr & 0xFFFF];
  int readWord(int addr) =>
      memory[addr & 0xFFFF] | (memory[(addr + 1) & 0xFFFF] << 8);

  void writeByte(int addr, int value) {
    memory[addr & 0xFFFF] = value & 0xFF;
  }

  void writeWord(int addr, int value) {
    memory[addr & 0xFFFF] = value & 0xFF;
    memory[(addr + 1) & 0xFFFF] = (value >> 8) & 0xFF;
  }

  // ── Stack ────────────────────────────────────────────────────────────────
  void pushWord(int value) {
    sp = (sp - 2) & 0xFFFF;
    writeWord(sp, value);
  }

  int popWord() {
    final v = readWord(sp);
    sp = (sp + 2) & 0xFFFF;
    return v;
  }

  // ── Register access by name ──────────────────────────────────────────────
  int getReg(String name) {
    switch (name.toUpperCase()) {
      case 'AX': return ax;
      case 'BX': return bx;
      case 'CX': return cx;
      case 'DX': return dx;
      case 'SI': return si;
      case 'DI': return di;
      case 'SP': return sp;
      case 'BP': return bp;
      case 'CS': return cs;
      case 'DS': return ds;
      case 'SS': return ss;
      case 'ES': return es;
      case 'IP': return ip;
      case 'AH': return ah;
      case 'AL': return al;
      case 'BH': return bh;
      case 'BL': return bl;
      case 'CH': return ch;
      case 'CL': return cl;
      case 'DH': return dh;
      case 'DL': return dl;
      default: throw ArgumentError('Unknown register: $name');
    }
  }

  void setReg(String name, int value) {
    switch (name.toUpperCase()) {
      case 'AX': ax = value & 0xFFFF; break;
      case 'BX': bx = value & 0xFFFF; break;
      case 'CX': cx = value & 0xFFFF; break;
      case 'DX': dx = value & 0xFFFF; break;
      case 'SI': si = value & 0xFFFF; break;
      case 'DI': di = value & 0xFFFF; break;
      case 'SP': sp = value & 0xFFFF; break;
      case 'BP': bp = value & 0xFFFF; break;
      case 'CS': cs = value & 0xFFFF; break;
      case 'DS': ds = value & 0xFFFF; break;
      case 'SS': ss = value & 0xFFFF; break;
      case 'ES': es = value & 0xFFFF; break;
      case 'IP': ip = value & 0xFFFF; break;
      case 'AH': ah = value & 0xFF; break;
      case 'AL': al = value & 0xFF; break;
      case 'BH': bh = value & 0xFF; break;
      case 'BL': bl = value & 0xFF; break;
      case 'CH': ch = value & 0xFF; break;
      case 'CL': cl = value & 0xFF; break;
      case 'DH': dh = value & 0xFF; break;
      case 'DL': dl = value & 0xFF; break;
    }
  }

  bool is8BitReg(String name) {
    const regs8 = {'AH','AL','BH','BL','CH','CL','DH','DL'};
    return regs8.contains(name.toUpperCase());
  }

  // ── Reset ────────────────────────────────────────────────────────────────
  void reset() {
    ax = bx = cx = dx = si = di = bp = 0;
    sp = 0xFFFE;
    cs = ds = ss = es = 0;
    ip = 0x0100;
    cf = pf = af = zf = sf = tf = ifl = df = of_ = false;
    memory.fillRange(0, memory.length, 0);
    outputLog.clear();
    halted = false;
  }

  // ── Register snapshot for display ────────────────────────────────────────
  Map<String, int> snapshot() => {
    'AX': ax, 'BX': bx, 'CX': cx, 'DX': dx,
    'SP': sp, 'BP': bp, 'SI': si, 'DI': di,
    'DS': ds, 'ES': es, 'SS': ss, 'CS': cs,
    'IP': ip,
  };
}
