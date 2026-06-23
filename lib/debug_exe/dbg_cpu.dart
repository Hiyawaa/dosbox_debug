// lib/debug_exe/dbg_cpu.dart
//
// A byte-accurate 8086 CPU + 1MB segmented memory model, built specifically
// to back a recreation of MS-DOS DEBUG.EXE. This is intentionally separate
// from models/cpu8086.dart (which powers the label-based IDE interpreter) —
// DEBUG.EXE operates on real bytes at real segment:offset addresses, so it
// needs a real memory image and a real encoder/decoder, not a label table.

class DbgCpu {
  // General purpose registers (16-bit)
  int ax = 0, bx = 0, cx = 0, dx = 0;
  int si = 0, di = 0, bp = 0, sp = 0xFFEE;
  // Segment registers
  int cs = 0, ds = 0, ss = 0, es = 0;
  int ip = 0x0100;

  // Flags (8086 FLAGS register, bit layout matches real hardware)
  bool cf = false; // carry      bit 0
  bool pf = false; // parity     bit 2
  bool af = false; // aux carry  bit 4
  bool zf = false; // zero       bit 6
  bool sf = false; // sign       bit 7
  bool tf = false; // trap       bit 8
  bool ifl = true; // interrupt  bit 9
  bool df = false; // direction  bit 10
  bool of = false; // overflow   bit 11

  // 1MB addressable memory (real mode address space)
  static const int memSize = 0x100000;
  final List<int> memory = List<int>.filled(memSize, 0);

  bool halted = false;
  final List<String> output = [];

  // High/low byte accessors
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

  /// Linear (20-bit) address from a segment:offset pair.
  static int linear(int seg, int off) =>
      ((seg & 0xFFFF) << 4) + (off & 0xFFFF) & 0xFFFFF;

  int csip() => linear(cs, ip);

  int readByte(int seg, int off) => memory[linear(seg, off)];
  void writeByte(int seg, int off, int val) =>
      memory[linear(seg, off)] = val & 0xFF;

  int readWord(int seg, int off) {
    final lo = readByte(seg, off);
    final hi = readByte(seg, (off + 1) & 0xFFFF);
    return lo | (hi << 8);
  }

  void writeWord(int seg, int off, int val) {
    writeByte(seg, off, val & 0xFF);
    writeByte(seg, (off + 1) & 0xFFFF, (val >> 8) & 0xFF);
  }

  int readByteLin(int lin) => memory[lin & 0xFFFFF];
  void writeByteLin(int lin, int val) => memory[lin & 0xFFFFF] = val & 0xFF;

  void pushWord(int value) {
    sp = (sp - 2) & 0xFFFF;
    writeWord(ss, sp, value);
  }

  int popWord() {
    final v = readWord(ss, sp);
    sp = (sp + 2) & 0xFFFF;
    return v;
  }

  int getReg16(String name) {
    switch (name.toUpperCase()) {
      case 'AX':
        return ax;
      case 'BX':
        return bx;
      case 'CX':
        return cx;
      case 'DX':
        return dx;
      case 'SI':
        return si;
      case 'DI':
        return di;
      case 'SP':
        return sp;
      case 'BP':
        return bp;
      case 'CS':
        return cs;
      case 'DS':
        return ds;
      case 'SS':
        return ss;
      case 'ES':
        return es;
      case 'IP':
        return ip;
      default:
        throw ArgumentError('Unknown register: $name');
    }
  }

  void setReg16(String name, int value) {
    value &= 0xFFFF;
    switch (name.toUpperCase()) {
      case 'AX':
        ax = value;
        break;
      case 'BX':
        bx = value;
        break;
      case 'CX':
        cx = value;
        break;
      case 'DX':
        dx = value;
        break;
      case 'SI':
        si = value;
        break;
      case 'DI':
        di = value;
        break;
      case 'SP':
        sp = value;
        break;
      case 'BP':
        bp = value;
        break;
      case 'CS':
        cs = value;
        break;
      case 'DS':
        ds = value;
        break;
      case 'SS':
        ss = value;
        break;
      case 'ES':
        es = value;
        break;
      case 'IP':
        ip = value;
        break;
      default:
        throw ArgumentError('Unknown register: $name');
    }
  }

  int getReg8(String name) {
    switch (name.toUpperCase()) {
      case 'AL':
        return al;
      case 'AH':
        return ah;
      case 'BL':
        return bl;
      case 'BH':
        return bh;
      case 'CL':
        return cl;
      case 'CH':
        return ch;
      case 'DL':
        return dl;
      case 'DH':
        return dh;
      default:
        throw ArgumentError('Unknown register: $name');
    }
  }

  void setReg8(String name, int value) {
    value &= 0xFF;
    switch (name.toUpperCase()) {
      case 'AL':
        al = value;
        break;
      case 'AH':
        ah = value;
        break;
      case 'BL':
        bl = value;
        break;
      case 'BH':
        bh = value;
        break;
      case 'CL':
        cl = value;
        break;
      case 'CH':
        ch = value;
        break;
      case 'DL':
        dl = value;
        break;
      case 'DH':
        dh = value;
        break;
      default:
        throw ArgumentError('Unknown register: $name');
    }
  }

  /// 16-bit flags register value, bit layout matching real 8086 hardware
  /// (bit 1 and other reserved bits forced as DEBUG.EXE displays them).
  int get flagsWord {
    int f = 0x0002; // bit 1 always set on real hardware
    if (cf) f |= 0x0001;
    if (pf) f |= 0x0004;
    if (af) f |= 0x0010;
    if (zf) f |= 0x0040;
    if (sf) f |= 0x0080;
    if (tf) f |= 0x0100;
    if (ifl) f |= 0x0200;
    if (df) f |= 0x0400;
    if (of) f |= 0x0800;
    return f;
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
    of = (f & 0x0800) != 0;
  }

  /// DEBUG.EXE's flag mnemonic display, in its fixed order:
  /// OF DF IF SF ZF AF PF CF -> e.g. "NV UP EI PL NZ NA PO NC"
  String flagsDisplay() {
    return [
      of ? 'OV' : 'NV',
      df ? 'DN' : 'UP',
      ifl ? 'EI' : 'DI',
      sf ? 'NG' : 'PL',
      zf ? 'ZR' : 'NZ',
      af ? 'AC' : 'NA',
      pf ? 'PE' : 'PO',
      cf ? 'CY' : 'NC',
    ].join(' ');
  }

  void updateFlagsAdd8(int a, int b, int result) {
    final masked = result & 0xFF;
    zf = masked == 0;
    sf = (masked & 0x80) != 0;
    cf = result > 0xFF || result < 0;
    of = (((a ^ b ^ 0x80) & (result ^ a)) & 0x80) != 0;
    af = ((a ^ b ^ masked) & 0x10) != 0;
    pf = _parity(masked);
  }

  void updateFlagsAdd16(int a, int b, int result) {
    final masked = result & 0xFFFF;
    zf = masked == 0;
    sf = (masked & 0x8000) != 0;
    cf = result > 0xFFFF || result < 0;
    of = (((a ^ b ^ 0x8000) & (result ^ a)) & 0x8000) != 0;
    af = ((a ^ b ^ masked) & 0x10) != 0;
    pf = _parity(masked & 0xFF);
  }

  void updateFlagsSub8(int a, int b, int result) {
    final masked = result & 0xFF;
    zf = masked == 0;
    sf = (masked & 0x80) != 0;
    cf = a < b;
    of = (((a ^ b) & (a ^ masked)) & 0x80) != 0;
    af = ((a ^ b ^ masked) & 0x10) != 0;
    pf = _parity(masked);
  }

  void updateFlagsSub16(int a, int b, int result) {
    final masked = result & 0xFFFF;
    zf = masked == 0;
    sf = (masked & 0x8000) != 0;
    cf = a < b;
    of = (((a ^ b) & (a ^ masked)) & 0x8000) != 0;
    af = ((a ^ b ^ masked) & 0x10) != 0;
    pf = _parity(masked & 0xFF);
  }

  void updateFlagsLogic8(int result) {
    final masked = result & 0xFF;
    zf = masked == 0;
    sf = (masked & 0x80) != 0;
    cf = false;
    of = false;
    pf = _parity(masked);
  }

  void updateFlagsLogic16(int result) {
    final masked = result & 0xFFFF;
    zf = masked == 0;
    sf = (masked & 0x8000) != 0;
    cf = false;
    of = false;
    pf = _parity(masked & 0xFF);
  }

  static bool _parity(int v) {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if ((v >> i) & 1 == 1) count++;
    }
    return count % 2 == 0;
  }

  void reset() {
    ax = bx = cx = dx = si = di = bp = 0;
    sp = 0xFFEE;
    cs = ds = ss = es = 0;
    ip = 0x0100;
    cf = pf = af = zf = sf = tf = df = of = false;
    ifl = true;
    memory.fillRange(0, memory.length, 0);
    output.clear();
    halted = false;
  }
}
