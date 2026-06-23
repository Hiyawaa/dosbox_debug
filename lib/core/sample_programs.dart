// lib/core/sample_programs.dart
// Built-in example programs demonstrating all 19 instructions

class SampleProgram {
  final String name;
  final String description;
  final String code;
  const SampleProgram(this.name, this.description, this.code);
}

const samplePrograms = [
  SampleProgram(
    'Hello World',
    'INT 21h to print a string using DB',
    '''; Hello World - 8086 Assembly
; Uses: ORG, DB, MOV, INT

ORG 100h

START:
    MOV AH, 09h       ; DOS print string function
    MOV DX, MSG       ; Address of message
    INT 21h           ; Call DOS

    MOV AH, 4Ch       ; Exit function
    INT 21h

MSG DB 'Hello, 8086 World!', 0Dh, 0Ah, '\$'
''',
  ),

  SampleProgram(
    'Arithmetic Suite',
    'ADD SUB MUL DIV all in one',
    '''; Arithmetic Demo
; Tests: MOV, ADD, SUB, MUL, DIV

ORG 100h

START:
    ; --- ADD ---
    MOV AX, 100       ; AX = 100
    MOV BX, 250       ; BX = 250
    ADD AX, BX        ; AX = 350

    ; --- SUB ---
    MOV CX, AX        ; CX = 350
    SUB CX, 50        ; CX = 300

    ; --- MUL ---
    MOV AX, 12        ; AX = 12
    MOV BX, 5         ; BX = 5
    MUL BX            ; DX:AX = 60

    ; --- DIV ---
    MOV AX, 100       ; AX = 100
    MOV BX, 4         ; divisor
    DIV BX            ; AX = 25, DX = 0

    MOV AH, 4Ch
    INT 21h
''',
  ),

  SampleProgram(
    'Loop Counter',
    'LOOP instruction counting down CX',
    '''; Loop Counter
; Uses: MOV, ADD, LOOP, INC, DEC

ORG 100h

START:
    MOV AX, 0         ; accumulator
    MOV CX, 10        ; loop 10 times
    MOV BX, 5         ; step value

COUNT_LOOP:
    ADD AX, BX        ; AX += 5
    INC BX            ; BX++ each iteration
    LOOP COUNT_LOOP   ; CX-- if CX!=0, jump

    ; AX = 5+6+7+8+9+10+11+12+13+14 = 95
    MOV AH, 4Ch
    INT 21h
''',
  ),

  SampleProgram(
    'Stack & Subroutine',
    'PUSH POP CALL RET demo',
    '''; Stack & Subroutine Demo
; Uses: MOV, PUSH, POP, CALL, RET, ADD

ORG 100h

START:
    MOV AX, 10
    MOV BX, 20
    PUSH AX            ; save AX
    PUSH BX            ; save BX

    CALL ADD_THEM      ; AX = AX + BX

    POP BX             ; restore BX
    POP AX             ; restore AX (original)
    ; now CX holds the sum from subroutine

    MOV AH, 4Ch
    INT 21h

; Subroutine: CX = AX + BX
ADD_THEM:
    MOV CX, AX
    ADD CX, BX
    RET
''',
  ),

  SampleProgram(
    'Conditional Jumps',
    'JMP JE JNE - branching logic',
    '''; Conditional Branching
; Uses: MOV, CMP, JE, JNE, JMP, SUB

ORG 100h

START:
    MOV AX, 42
    MOV BX, 42
    SUB AX, BX        ; AX=0, sets ZF=1

    JE  EQUAL         ; jump if ZF=1
    JMP NOT_EQUAL

EQUAL:
    MOV CX, 1111h     ; CX = 1111h (equal marker)
    JMP DONE

NOT_EQUAL:
    MOV CX, 0FFFFh    ; CX = FFFFh (not equal)

DONE:
    MOV AX, 99
    MOV BX, 50
    SUB AX, BX        ; AX=49, ZF=0

    JNE THEY_DIFFER
    MOV DX, 0
    JMP EXIT

THEY_DIFFER:
    MOV DX, 1         ; DX=1 means different

EXIT:
    MOV AH, 4Ch
    INT 21h
''',
  ),

  SampleProgram(
    'INC/DEC Counter',
    'Increment and Decrement registers',
    '''; INC / DEC Demo
; Uses: MOV, INC, DEC, LOOP, PUSH, POP

ORG 100h

START:
    MOV AX, 0
    MOV BX, 100

UP_LOOP:
    INC AX            ; count up
    DEC BX            ; count down
    PUSH AX
    PUSH BX
    POP  BX
    POP  AX
    CMP BX, 50
    JNE UP_LOOP       ; loop until BX=50

    ; AX=50, BX=50 here
    MOV AH, 4Ch
    INT 21h
''',
  ),

  SampleProgram(
    'Memory with DB/DW',
    'Store and load bytes and words',
    '''; Memory Data Demo
; Uses: ORG, DB, DW, MOV, ADD

ORG 100h

START:
    MOV AX, [WORD1]   ; load word from memory
    MOV BX, [WORD2]
    ADD AX, BX        ; AX = WORD1 + WORD2

    MOV AL, [BYTE1]   ; load byte
    MOV BL, [BYTE2]
    ADD AL, BL        ; AL = BYTE1 + BYTE2

    MOV AH, 4Ch
    INT 21h

; Data section
BYTE1 DB 0Ah          ; 10
BYTE2 DB 14h          ; 20
WORD1 DW 1000h        ; 4096
WORD2 DW 0200h        ; 512
''',
  ),
];
