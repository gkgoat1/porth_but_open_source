// In progress rewrite of ./porth.py in Porth

// TODO: support for include path searching
m4_changequote([<,>])
include "std/std.porth"
m4_ifdef([<USE_TLSF>],[<
include "std/tlsf.porth"
memory heap 640K end
memory heapidx sizeof(ptr) end
heapidx heap 640000 tlsf::new !ptr
proc malloc int -- ptr in
heapidx @ptr swap tlsf::malloc
end
proc free ptr -- in
heapidx @ptr swap tlsf::free
end
proc strdup int ptr -- int ptr int ptr in 
2dup drop swap dup malloc
end
>])
m4_ifdef([<USE_DL>],[<
proc dlopen int ptr -- ptr in
str-to-cstr call-extern dlopen
end
proc dlsym ptr int ptr int ptr -- ptr in
str-to-cstr rot str-to-cstr swap call-extern dlvsym
end
>])
m4_define([<scall>],[<call-extern-raw null>])
const OP_PUSH_INT        1 offset end
const OP_PUSH_LOCAL_MEM  1 offset end
const OP_PUSH_GLOBAL_MEM 1 offset end
const OP_PUSH_STR        1 offset end
const OP_PUSH_CSTR       1 offset end
const OP_IF              1 offset end
const OP_IFSTAR          1 offset end
const OP_ELSE            1 offset end
const OP_END             1 offset end
const OP_SKIP_PROC       1 offset end
const OP_PREP_PROC       1 offset end
const OP_RET             1 offset end
const OP_CALL            1 offset end
const OP_WHILE           1 offset end
const OP_DO              1 offset end
const OP_INTRINSIC       1 offset end
const COUNT_OPS             reset end

proc op-type-as-str
  int // Op type
  --
  int ptr // str
in
  assert "Exhaustive handling of Op types in print-op-type" COUNT_OPS 16 = end
       dup OP_PUSH_INT        =  if  "OP_PUSH_INT"
  else dup OP_PUSH_LOCAL_MEM  =  if* "OP_PUSH_LOCAL_MEM"
  else dup OP_PUSH_GLOBAL_MEM =  if* "OP_PUSH_GLOBAL_MEM"
  else dup OP_PUSH_STR        =  if* "OP_PUSH_STR"
  else dup OP_PUSH_CSTR       =  if* "OP_PUSH_CSTR"
  else dup OP_INTRINSIC       =  if* "OP_INTRINSIC"
  else dup OP_IF              =  if* "OP_IF"
  else dup OP_IFSTAR          =  if* "OP_IFSTAR"
  else dup OP_ELSE            =  if* "OP_ELSE"
  else dup OP_END             =  if* "OP_END"
  else dup OP_SKIP_PROC       =  if* "OP_SKIP_PROC"
  else dup OP_PREP_PROC       =  if* "OP_PREP_PROC"
  else dup OP_RET             =  if* "OP_RET"
  else dup OP_CALL            =  if* "OP_CALL"
  else dup OP_WHILE           =  if* "OP_WHILE"
  else dup OP_DO              =  if* "OP_DO"
  else
    here eputs ": Unknown op type\n" eputs 1 exit
    0 NULL
  end
  rot drop
end

const Loc.file-path sizeof(Str) offset end
const Loc.row sizeof(u64) offset end
const Loc.col sizeof(u64) offset end
const sizeof(Loc) reset end

proc fputloc ptr int in
  memory fd sizeof(u64) end
  fd !64
  dup Loc.file-path + @Str fd @64 fputs
  ":"                      fd @64 fputs
  dup Loc.row + @64        fd @64 fputu
  ":"                      fd @64 fputs
  dup Loc.col + @64        fd @64 fputu
  drop
end
proc putloc ptr in stdout fputloc end
proc eputloc ptr in stderr fputloc end

const TOKEN_INT  1 offset end
const TOKEN_WORD 1 offset end
const TOKEN_STR  1 offset end
const TOKEN_CSTR 1 offset end
const TOKEN_CHAR 1 offset end
const COUNT_TOKENS reset end

const Token.type sizeof(u64) offset end
const Token.loc  sizeof(Loc) offset end
const Token.text sizeof(Str) offset end
const Token.value
   sizeof(u64)
   sizeof(Str) max
   offset
end
const sizeof(Token) reset end

const Op.type sizeof(u64) offset end
const Op.operand sizeof(u64) offset end
const Op.token sizeof(Token) offset end
const Op.flags sizeof(u64) offset end
const sizeof(Op) reset end

const Op.EXTERN 1 end
const Op.RAW 2 end

const OPS_CAP 16 1024 * end
memory ops-count sizeof(u64) end
memory ops sizeof(Op) OPS_CAP * end

proc append-item
  int // item size
  ptr // item
  int // array capacity
  ptr // array
  ptr // array count
  --
  int  // index of the appended item
  bool // true - appended, false - not enough space
in
  memory count sizeof(ptr) end
  count !ptr
  memory array sizeof(ptr) end
  array !ptr

  count @ptr @int > if
    over
    count @ptr @int *
    array @ptr +
    memcpy drop

    count @ptr @int
    count @ptr inc64

    true
  else
    2drop
    0 false
  end
end


proc push-op
  int // type
  int // operand
  ptr // token
in
  memory op sizeof(Op) end
  sizeof(Token) swap op Op.token + memcpy drop
  op Op.operand + !int
  op Op.type + !int

  sizeof(Op) op OPS_CAP ops ops-count append-item lnot if
    here eputs ": ERROR: ops overflow\n" eputs 1 exit
  end
  drop
end
proc push-op-f
  int // type
  int // operand
  int
  ptr // token
in
  memory op sizeof(Op) end
  swap op Op.flags + !int
  sizeof(Token) swap op Op.token + memcpy drop
  op Op.operand + !int
  op Op.type + !int

  sizeof(Op) op OPS_CAP ops ops-count append-item lnot if
    here eputs ": ERROR: ops overflow\n" eputs 1 exit
  end
  drop
end

const STRLITS_CAP 1024 end
memory strlits-count sizeof(int) end
memory strlits sizeof(Str) STRLITS_CAP * end

proc strlit-define
  int ptr
  --
  int
in
  memory strlit sizeof(Str) end
  strlit !Str

  sizeof(Str) strlit
  STRLITS_CAP strlits
  strlits-count
  append-item lnot if
    here eputs ": ERROR: string literals capacity exceeded\n" eputs
    1 exit
  end
end

const STRBUF_CAP 16 1024 * end
memory strbuf-size sizeof(int) end
memory strbuf-start STRBUF_CAP end

proc strbuf-end -- ptr in strbuf-start strbuf-size @int + end
proc strbuf-append-char int in
  strbuf-size @int STRBUF_CAP >= if
    here eputs ": Assertion Failed: string literal buffer overflow\n" eputs
    1 exit
  end

  strbuf-end !8
  strbuf-size inc64
end
proc strbuf-append-str int ptr in
  memory str sizeof(Str) end
  str !Str

  while str @Str.count 0 > do
    str @Str.data @8 strbuf-append-char
    str str-chop-one-left
  end
end

proc tmp-utos
  int
  --
  int ptr
in
  memory buffer sizeof(ptr) end
  PUTU_BUFFER_CAP m4_ifdef([<USE_TLSF>],malloc,tmp-alloc) buffer !ptr

  dup 0 = if
    drop
    buffer @ptr PUTU_BUFFER_CAP + 1 -
    '0' over !64
    1 swap
  else
    buffer @ptr PUTU_BUFFER_CAP +
    while over 0 > do
      1 - dup rot
      10 divmod
      rot swap '0' + swap !8 swap
    end

    swap drop

    dup buffer @ptr PUTU_BUFFER_CAP + swap - swap
  end
end

proc strbuf-loc
  ptr // loc
  --
  int ptr
in
  memory start sizeof(ptr) end
  memory a sizeof(ptr) end
  memory b sizeof(ptr) end
  strbuf-end start !ptr

  dup Loc.file-path + @Str   strbuf-append-str
  ":"                        strbuf-append-str
  dup Loc.row + @64 tmp-utos dup a !ptr strbuf-append-str
  ":"                        strbuf-append-str
  dup Loc.col + @64 tmp-utos dup b !ptr strbuf-append-str
  drop

  strbuf-end start @ptr -
  start @ptr
  m4_ifdef([<USE_TLSF>],a @ptr free)
  m4_ifdef([<USE_TLSF>],b @ptr free)
end

const INTRINSIC_PLUS      1 offset end
const INTRINSIC_MINUS     1 offset end
const INTRINSIC_MUL       1 offset end
const INTRINSIC_DIVMOD    1 offset end
const INTRINSIC_MAX       1 offset end
const INTRINSIC_EQ        1 offset end
const INTRINSIC_GT        1 offset end
const INTRINSIC_LT        1 offset end
const INTRINSIC_GE        1 offset end
const INTRINSIC_LE        1 offset end
const INTRINSIC_NE        1 offset end
const INTRINSIC_SHR       1 offset end
const INTRINSIC_SHL       1 offset end
const INTRINSIC_OR        1 offset end
const INTRINSIC_AND       1 offset end
const INTRINSIC_NOT       1 offset end
const INTRINSIC_PRINT     1 offset end
const INTRINSIC_DUP       1 offset end
const INTRINSIC_SWAP      1 offset end
const INTRINSIC_DROP      1 offset end
const INTRINSIC_OVER      1 offset end
const INTRINSIC_ROT       1 offset end
const INTRINSIC_LOAD8     1 offset end
const INTRINSIC_STORE8    1 offset end
const INTRINSIC_LOAD16    1 offset end
const INTRINSIC_STORE16   1 offset end
const INTRINSIC_LOAD32    1 offset end
const INTRINSIC_STORE32   1 offset end
const INTRINSIC_LOAD64    1 offset end
const INTRINSIC_STORE64   1 offset end
const INTRINSIC_CAST_PTR  1 offset end
const INTRINSIC_CAST_INT  1 offset end
const INTRINSIC_CAST_BOOL 1 offset end
const INTRINSIC_ARGC      1 offset end
const INTRINSIC_ARGV      1 offset end
const INTRINSIC_ENVP      1 offset end
const INTRINSIC_SYSCALL0  1 offset end
const INTRINSIC_SYSCALL1  1 offset end
const INTRINSIC_SYSCALL2  1 offset end
const INTRINSIC_SYSCALL3  1 offset end
const INTRINSIC_SYSCALL4  1 offset end
const INTRINSIC_SYSCALL5  1 offset end
const INTRINSIC_SYSCALL6  1 offset end
const COUNT_INTRINSICS       reset end

proc intrinsic-name
  int // intrinsic
  --
  int ptr // name
in
  assert "Exhaustive handling of Intrinsics in intrinsic-by-name" COUNT_INTRINSICS 43 = end
       dup INTRINSIC_PLUS      = if  drop "+"
  else dup INTRINSIC_MINUS     = if* drop "-"
  else dup INTRINSIC_MUL       = if* drop "*"
  else dup INTRINSIC_DIVMOD    = if* drop "divmod"
  else dup INTRINSIC_MAX       = if* drop "max"
  else dup INTRINSIC_PRINT     = if* drop "print"
  else dup INTRINSIC_EQ        = if* drop "="
  else dup INTRINSIC_GT        = if* drop ">"
  else dup INTRINSIC_LT        = if* drop "<"
  else dup INTRINSIC_GE        = if* drop ">="
  else dup INTRINSIC_LE        = if* drop "<="
  else dup INTRINSIC_NE        = if* drop "!="
  else dup INTRINSIC_SHR       = if* drop "shr"
  else dup INTRINSIC_SHL       = if* drop "shl"
  else dup INTRINSIC_OR        = if* drop "or"
  else dup INTRINSIC_AND       = if* drop "and"
  else dup INTRINSIC_NOT       = if* drop "not"
  else dup INTRINSIC_DUP       = if* drop "dup"
  else dup INTRINSIC_SWAP      = if* drop "swap"
  else dup INTRINSIC_DROP      = if* drop "drop"
  else dup INTRINSIC_OVER      = if* drop "over"
  else dup INTRINSIC_ROT       = if* drop "rot"
  else dup INTRINSIC_STORE8    = if* drop "!8"
  else dup INTRINSIC_LOAD8     = if* drop "@8"
  else dup INTRINSIC_STORE16   = if* drop "!16"
  else dup INTRINSIC_LOAD16    = if* drop "@16"
  else dup INTRINSIC_STORE32   = if* drop "!32"
  else dup INTRINSIC_LOAD32    = if* drop "@32"
  else dup INTRINSIC_STORE64   = if* drop "!64"
  else dup INTRINSIC_LOAD64    = if* drop "@64"
  else dup INTRINSIC_CAST_PTR  = if* drop "cast(ptr)"
  else dup INTRINSIC_CAST_INT  = if* drop "cast(int)"
  else dup INTRINSIC_CAST_BOOL = if* drop "cast(bool)"
  else dup INTRINSIC_ARGC      = if* drop "argc"
  else dup INTRINSIC_ARGV      = if* drop "argv"
  else dup INTRINSIC_ENVP      = if* drop "envp"
  else dup INTRINSIC_SYSCALL0  = if* drop "syscall0"
  else dup INTRINSIC_SYSCALL1  = if* drop "syscall1"
  else dup INTRINSIC_SYSCALL2  = if* drop "syscall2"
  else dup INTRINSIC_SYSCALL3  = if* drop "syscall3"
  else dup INTRINSIC_SYSCALL4  = if* drop "syscall4"
  else dup INTRINSIC_SYSCALL5  = if* drop "syscall5"
  else dup INTRINSIC_SYSCALL6  = if* drop "syscall6"
  else
    drop 0 NULL
    here eputs ": unreachable\n" eputs
    1 exit
  end
end

proc intrinsic-by-name
  int ptr // name
  --
  int     // intrinsic
  bool    // found
in
  memory name sizeof(Str) end
  name !Str
  true
  assert "Exhaustive handling of Intrinsics in intrinsic-by-name" COUNT_INTRINSICS 43 = end
       name @Str "+"          streq if  INTRINSIC_PLUS
  else name @Str "-"          streq if* INTRINSIC_MINUS
  else name @Str "*"          streq if* INTRINSIC_MUL
  else name @Str "divmod"     streq if* INTRINSIC_DIVMOD
  else name @Str "max"        streq if* INTRINSIC_MAX
  else name @Str "print"      streq if* INTRINSIC_PRINT
  else name @Str "="          streq if* INTRINSIC_EQ
  else name @Str ">"          streq if* INTRINSIC_GT
  else name @Str "<"          streq if* INTRINSIC_LT
  else name @Str ">="         streq if* INTRINSIC_GE
  else name @Str "<="         streq if* INTRINSIC_LE
  else name @Str "!="         streq if* INTRINSIC_NE
  else name @Str "shr"        streq if* INTRINSIC_SHR
  else name @Str "shl"        streq if* INTRINSIC_SHL
  else name @Str "or"         streq if* INTRINSIC_OR
  else name @Str "and"        streq if* INTRINSIC_AND
  else name @Str "not"        streq if* INTRINSIC_NOT
  else name @Str "dup"        streq if* INTRINSIC_DUP
  else name @Str "swap"       streq if* INTRINSIC_SWAP
  else name @Str "drop"       streq if* INTRINSIC_DROP
  else name @Str "over"       streq if* INTRINSIC_OVER
  else name @Str "rot"        streq if* INTRINSIC_ROT
  else name @Str "!8"         streq if* INTRINSIC_STORE8
  else name @Str "@8"         streq if* INTRINSIC_LOAD8
  else name @Str "!16"        streq if* INTRINSIC_STORE16
  else name @Str "@16"        streq if* INTRINSIC_LOAD16
  else name @Str "!32"        streq if* INTRINSIC_STORE32
  else name @Str "@32"        streq if* INTRINSIC_LOAD32
  else name @Str "!64"        streq if* INTRINSIC_STORE64
  else name @Str "@64"        streq if* INTRINSIC_LOAD64
  else name @Str "cast(ptr)"  streq if* INTRINSIC_CAST_PTR
  else name @Str "cast(int)"  streq if* INTRINSIC_CAST_INT
  else name @Str "cast(bool)" streq if* INTRINSIC_CAST_BOOL
  else name @Str "argc"       streq if* INTRINSIC_ARGC
  else name @Str "argv"       streq if* INTRINSIC_ARGV
  else name @Str "envp"       streq if* INTRINSIC_ENVP
  else name @Str "syscall0"   streq if* INTRINSIC_SYSCALL0
  else name @Str "syscall1"   streq if* INTRINSIC_SYSCALL1
  else name @Str "syscall2"   streq if* INTRINSIC_SYSCALL2
  else name @Str "syscall3"   streq if* INTRINSIC_SYSCALL3
  else name @Str "syscall4"   streq if* INTRINSIC_SYSCALL4
  else name @Str "syscall5"   streq if* INTRINSIC_SYSCALL5
  else name @Str "syscall6"   streq if* INTRINSIC_SYSCALL6
  else
    drop false 0
  end
  swap
end

const Const.name  sizeof(Str) offset end
const Const.loc   sizeof(Loc) offset end
const Const.value sizeof(u64) offset end
const Const.type  sizeof(u64) offset end
const sizeof(Const) reset end

const CONST_CAP 1024 end
memory consts sizeof(Const) CONST_CAP * end
memory consts-count sizeof(u64) end

proc const-lookup
  int ptr // name
  --
  ptr     // ptr to const struct
in
  memory name sizeof(Str) end
  name !Str

  0 while
    dup consts-count @64 < if
      dup sizeof(Const) * consts + Const.name + @Str
      name @Str
      streq
      lnot
    else false end
  do 1 + end

  dup consts-count @64 < if
    sizeof(Const) * consts +
  else
    drop NULL
  end
end

proc const-define
  ptr // ptr to const struct
in
  sizeof(Const) swap CONST_CAP consts consts-count append-item lnot if
    here eputs ": ERROR: constants definitions capacity exceeded\n" eputs
    1 exit
  end
  drop
end

const Proc.name sizeof(Str) offset end
const Proc.addr sizeof(u64) offset end
const Proc.loc sizeof(Loc) offset end
const sizeof(Proc) reset end
const PROCS_CAP 1024 end
memory procs-count sizeof(u64) end
memory procs sizeof(Proc) PROCS_CAP * end
memory inside-proc sizeof(bool) end

proc proc-lookup
  int ptr // proc name
  --
  ptr     // proc
in
  memory name sizeof(Str) end
  name !Str

  0 while
    dup procs-count @64 < if
      dup sizeof(Proc) * procs + Proc.name + @Str
      name @Str
      streq
      lnot
    else false end
  do 1 + end

  dup procs-count @64 < if
    sizeof(Proc) * procs +
  else
    drop NULL
  end
end

proc proc-define
  ptr // proc
in
  sizeof(Proc) swap PROCS_CAP procs procs-count append-item lnot if
    here eputs ": ERROR: procedure definitions capacity exceeded\n" eputs
    1 exit
  end
  drop
end

const Memory.name sizeof(Str) offset end
const Memory.offset sizeof(u64) offset end
const Memory.loc sizeof(Loc) offset end
const sizeof(Memory) reset end

const GLOBAL_MEMORIES_CAP 1024 end
memory global-memories-count sizeof(u64) end
memory global-memories sizeof(Memory) GLOBAL_MEMORIES_CAP * end
memory global-memory-capacity sizeof(u64) end

const LOCAL_MEMORIES_CAP 1024 end
memory local-memories-count sizeof(u64) end
memory local-memories sizeof(Memory) LOCAL_MEMORIES_CAP * end
memory local-memory-capacity sizeof(u64) end

proc cmd-echoed ptr in
  memory wstatus sizeof(u64) end

  "[CMD]" puts
  dup while dup @64 0 != do
    " " puts
    // TODO: properly escape the logged CMD
    dup @64 cast(ptr) cstr-to-str puts
    8 +
  end drop
  "\n" puts

  fork

  dup 0 = if
    // argv[0] argv
    drop
    dup @ptr
    swap
    execvp
  else dup 0 > if*
    2drop
    // TODO: handle the result of wait4
    NULL
    0
    wstatus
    0 1 - //-1
    wait4
    drop
  else
    2drop
    "[ERROR] could not fork a child\n" eputs
    1 exit
  end
end

proc dump-ops in
  0 while dup ops-count @64 < do
    dup sizeof(Op) * ops +
    dup Op.token + Token.loc + putloc ": " puts
    over putu ": " puts dup Op.type + @64 op-type-as-str puts " " puts
    dup Op.type + @64 OP_INTRINSIC = if
      Op.operand + @64 intrinsic-name puts
    else
      Op.operand + @64 putu
    end
    "\n" puts
    1 +
  end
  drop
end

const MEM_CAPACITY 640000 end

proc located-here ptr in eputloc ": NOTE: located here\n" eputs end

const X86_64_RET_STACK_CAP 8192 end

proc fputdecstr
  int ptr
  int
in
  memory fd sizeof(u64) end
  fd !64

  memory str sizeof(Str) end
  str !Str

  memory byte 2 end

  memory first sizeof(bool) end
  true first !bool

  while str @Str.count 0 > do
    first @bool if
      false first !bool
    else
      ","    fd @64 fputs
    end

    str @Str.data @8 fd @64 fputu
    str str-chop-one-left
  end
end
const X64 1 offset end
const ALL_MODES reset end
proc generate-nasm-linux-x86_64 in
  "[INFO] Generating output.asm\n" puts

  memory out-fd sizeof(u64) end
  memory mode sizeof(u64) end
  mode !64
  420                     // mode
  O_CREAT O_WRONLY or O_TRUNC or  // flags
  // TODO: the output file path should be based on the input file path
  "output.asm"c        // pathname
  // TODO: this is lame, let's just support negative numbers properly
  0 100 - //AT_FDCWD
  openat
  out-fd !64

  out-fd @64 0 < if
    "[ERROR] could not open `output.asm`\n" eputs
    1 exit
  end

  "BITS 64\n"                              out-fd @64 fputs
  "segment .text\n"                        out-fd @64 fputs
  "print:\n"                               out-fd @64 fputs
  "    mov     r9, -3689348814741910323\n" out-fd @64 fputs
  "    sub     rsp, 40\n"                  out-fd @64 fputs
  "    mov     BYTE [rsp+31], 10\n"        out-fd @64 fputs
  "    lea     rcx, [rsp+30]\n"            out-fd @64 fputs
  ".L2:\n"                                 out-fd @64 fputs
  "    mov     rax, rdi\n"                 out-fd @64 fputs
  "    lea     r8, [rsp+32]\n"             out-fd @64 fputs
  "    mul     r9\n"                       out-fd @64 fputs
  "    mov     rax, rdi\n"                 out-fd @64 fputs
  "    sub     r8, rcx\n"                  out-fd @64 fputs
  "    shr     rdx, 3\n"                   out-fd @64 fputs
  "    lea     rsi, [rdx+rdx*4]\n"         out-fd @64 fputs
  "    add     rsi, rsi\n"                 out-fd @64 fputs
  "    sub     rax, rsi\n"                 out-fd @64 fputs
  "    add     eax, 48\n"                  out-fd @64 fputs
  "    mov     BYTE [rcx], al\n"           out-fd @64 fputs
  "    mov     rax, rdi\n"                 out-fd @64 fputs
  "    mov     rdi, rdx\n"                 out-fd @64 fputs
  "    mov     rdx, rcx\n"                 out-fd @64 fputs
  "    sub     rcx, 1\n"                   out-fd @64 fputs
  "    cmp     rax, 9\n"                   out-fd @64 fputs
  "    ja      .L2\n"                      out-fd @64 fputs
  "    lea     rax, [rsp+32]\n"            out-fd @64 fputs
  "    mov     edi, 1\n"                   out-fd @64 fputs
  "    sub     rdx, rax\n"                 out-fd @64 fputs
  "    xor     eax, eax\n"                 out-fd @64 fputs
  "    lea     rsi, [rsp+32+rdx]\n"        out-fd @64 fputs
  "    mov     rdx, r8\n"                  out-fd @64 fputs
  "    mov     rax, 1\n"                   out-fd @64 fputs
  "    syscall\n"                          out-fd @64 fputs
  "    add     rsp, 40\n"                  out-fd @64 fputs
  "    ret\n"                              out-fd @64 fputs
  "global _start\n"                        out-fd @64 fputs
  "_start:\n"                              out-fd @64 fputs
  "    mov [args_ptr], rsp\n"              out-fd @64 fputs
  "    mov rax, ret_stack_end\n"           out-fd @64 fputs
  "    mov [ret_stack_rsp], rax\n"         out-fd @64 fputs

  0 while dup ops-count @64 < do
    dup sizeof(Op) * ops +

    assert "Exhaustive handling of Op types in generate-nasm-linux-x86_64" COUNT_OPS 16 = end
    "addr_" out-fd @64 fputs
    over    out-fd @64 fputu
    ":\n"   out-fd @64 fputs

    dup Op.type + @64 OP_PUSH_INT = if
       "    mov rax, "        out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n"    out-fd @64 fputs
       "    push rax\n"       out-fd @64 fputs
    else dup Op.type + @64 OP_PUSH_LOCAL_MEM = if*
       "    mov rax, [ret_stack_rsp]\n" out-fd @64 fputs
       "    add rax, "                  out-fd @64 fputs
       dup Op.operand + @64             out-fd @64 fputu
       "\n"                             out-fd @64 fputs
       "    push rax\n"                 out-fd @64 fputs
    else dup Op.type + @64 OP_PUSH_GLOBAL_MEM = if*
       "    mov rax, mem\n" out-fd @64 fputs
       "    add rax, "      out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n"    out-fd @64 fputs
       "    push rax\n"     out-fd @64 fputs
    else dup Op.type + @64 OP_PUSH_STR = if*
       "    mov rax, " out-fd @64 fputs
         dup Op.operand + @64
         sizeof(Str) *
         strlits +
         @Str.count
         out-fd @64 fputu
       "\n" out-fd @64 fputs

       "    push rax\n"     out-fd @64 fputs
       "    push str_"      out-fd @64 fputs
       dup Op.operand + @64 out-fd @64 fputu
       "\n"                 out-fd @64 fputs
    else dup Op.type + @64 OP_PUSH_CSTR = if*
       "    push str_"      out-fd @64 fputs
       dup Op.operand + @64 out-fd @64 fputu
       "\n"                 out-fd @64 fputs
    else dup Op.type + @64 OP_IF = if*
       "    pop rax\n"       out-fd @64 fputs
       "    test rax, rax\n" out-fd @64 fputs
       "    jz addr_"        out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n" out-fd @64 fputs
    else dup Op.type + @64 OP_IFSTAR = if*
       "    pop rax\n"       out-fd @64 fputs
       "    test rax, rax\n" out-fd @64 fputs
       "    jz addr_"        out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n" out-fd @64 fputs
    else dup Op.type + @64 OP_ELSE = if*
       "    jmp addr_"       out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n" out-fd @64 fputs
    else dup Op.type + @64 OP_END = if*
       "    jmp addr_"       out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n" out-fd @64 fputs
    else dup Op.type + @64 OP_WHILE = if*
       // NOTE: nothing to generate. `while` is basically a label
    else dup Op.type + @64 OP_DO = if*
       "    pop rax\n"       out-fd @64 fputs
       "    test rax, rax\n" out-fd @64 fputs
       "    jz addr_" out-fd @64 fputs dup Op.operand + @64 out-fd @64 fputu "\n" out-fd @64 fputs
    else dup Op.type + @64 OP_SKIP_PROC = if*
       "    jmp addr_"      out-fd @64 fputs
       dup Op.operand + @64 out-fd @64 fputu
       "\n"                 out-fd @64 fputs
    else dup Op.type + @64 OP_PREP_PROC = if*
       "    sub rsp, "      out-fd @64 fputs
       dup Op.operand + @64 out-fd @64 fputu
       "\n"                 out-fd @64 fputs

       "    mov [ret_stack_rsp], rsp\n" out-fd @64 fputs
       "    mov rsp, rax\n"             out-fd @64 fputs
    else dup Op.type + @64 OP_RET = if*
    dup Op.flags Op.EXTERN and cast(bool) if
dup Op.operand cast(ptr) @Str out-fd @64 fputs
":\n" out-fd @64 fputs
    else
       "    mov rax, rsp\n"             out-fd @64 fputs
       "    mov rsp, [ret_stack_rsp]\n" out-fd @64 fputs
       "    add rsp, "                  out-fd @64 fputs
       dup Op.operand + @64             out-fd @64 fputu
       "\n"                             out-fd @64 fputs
       "    ret\n"                      out-fd @64 fputs
    end
    else dup Op.type + @64 OP_CALL = if*
       dup Op.flags Op.EXTERN and cast(bool) if
        dup Op.flags Op.RAW and cast(bool) if
        "pop rbx \n call rbx\n" out-fd @64 fputs
        else
            "call " out-fd @64 fputs
            dup Op.operand cast(ptr) @Str out-fd @64 fputs
            "\n" out-fd @64 fputs
          end
       else
            "    mov rax, rsp\n"             out-fd @64 fputs
            "    mov rsp, [ret_stack_rsp]\n" out-fd @64 fputs
            "    call addr_"                 out-fd @64 fputs
            dup Op.operand + @64             out-fd @64 fputu
            "\n"                             out-fd @64 fputs
            "    mov [ret_stack_rsp], rsp\n" out-fd @64 fputs
            "    mov rsp, rax\n"             out-fd @64 fputs
       end
    else dup Op.type + @64 OP_INTRINSIC = if*
        assert "Exhaustive handling of Intrinsics in generate-nasm-linux-x86_64"
          COUNT_INTRINSICS 43 =
        end
        dup Op.flags Op.EXTERN and cast(bool) if
        m4_ifdef([<USE_DL>],dup out-fd dup Op.operand + @Str dlopen "intrinsic" "1.0" dlsym scall)
        else
        dup Op.operand + @64
        dup INTRINSIC_PLUS = if
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    add rax, rbx\n"        out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_MINUS = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    sub rbx, rax\n"        out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_MUL = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    mul rbx\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_DIVMOD = if*
            "    xor rdx, rdx\n"        out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    div rbx\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
            "    push rdx\n"            out-fd @64 fputs
        else dup INTRINSIC_MAX = if*
            "    pop rax\n"         out-fd @64 fputs
            "    pop rbx\n"         out-fd @64 fputs
            "    cmp rbx, rax\n"    out-fd @64 fputs
            "    cmovge rax, rbx\n" out-fd @64 fputs
            "    push rax\n"        out-fd @64 fputs
        else dup INTRINSIC_SHR = if*
            "    pop rcx\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    shr rbx, cl\n"         out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_SHL = if*
            "    pop rcx\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    shl rbx, cl\n"         out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_OR = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    or rbx, rax\n"         out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_AND = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    and rbx, rax\n"        out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_NOT = if*
            "    pop rax\n"             out-fd @64 fputs
            "    not rax\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_PRINT = if*
            "    pop rdi\n"             out-fd @64 fputs
            "    call print\n"          out-fd @64 fputs
        else dup INTRINSIC_EQ = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmove rcx, rdx\n"      out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_GT = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmovg rcx, rdx\n"      out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_LT = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmovl rcx, rdx\n"      out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_GE = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmovge rcx, rdx\n"     out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_LE = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmovle rcx, rdx\n"     out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_NE = if*
            "    mov rcx, 0\n"          out-fd @64 fputs
            "    mov rdx, 1\n"          out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rax\n"             out-fd @64 fputs
            "    cmp rax, rbx\n"        out-fd @64 fputs
            "    cmovne rcx, rdx\n"     out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_DUP = if*
            "    pop rax\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SWAP = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_DROP = if*
            "    pop rax\n"             out-fd @64 fputs
        else dup INTRINSIC_OVER = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_ROT = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    pop rcx\n"             out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
            "    push rcx\n"            out-fd @64 fputs
        else dup INTRINSIC_LOAD8 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    xor rbx, rbx\n"        out-fd @64 fputs
            "    mov bl, [rax]\n"       out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_STORE8 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    mov [rax], bl\n"       out-fd @64 fputs
        else dup INTRINSIC_LOAD16 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    xor rbx, rbx\n"        out-fd @64 fputs
            "    mov bx, [rax]\n"       out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_STORE16 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    mov [rax], bx\n"       out-fd @64 fputs
        else dup INTRINSIC_LOAD32 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    xor rbx, rbx\n"        out-fd @64 fputs
            "    mov ebx, [rax]\n"      out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_STORE32 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    mov [rax], ebx\n"      out-fd @64 fputs
        else dup INTRINSIC_LOAD64 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    xor rbx, rbx\n"        out-fd @64 fputs
            "    mov rbx, [rax]\n"      out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_STORE64 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rbx\n"             out-fd @64 fputs
            "    mov [rax], rbx\n"      out-fd @64 fputs
        else dup INTRINSIC_ARGC = if*
            "    mov rax, [args_ptr]\n" out-fd @64 fputs
            "    mov rax, [rax]\n"      out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_ARGV = if*
            "    mov rax, [args_ptr]\n" out-fd @64 fputs
            "    add rax, 8\n"          out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_ENVP = if*
            "    mov rax, [args_ptr]\n" out-fd @64 fputs
            "    mov rax, [rax]\n"      out-fd @64 fputs
            "    add rax, 2\n"          out-fd @64 fputs
            "    shl rax, 3\n"          out-fd @64 fputs
            "    mov rbx, [args_ptr]\n" out-fd @64 fputs
            "    add rbx, rax\n"        out-fd @64 fputs
            "    push rbx\n"            out-fd @64 fputs
        else dup INTRINSIC_CAST_PTR = if*
        else dup INTRINSIC_CAST_INT = if*
        else dup INTRINSIC_CAST_BOOL = if*
        else dup INTRINSIC_SYSCALL0 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL1 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL2 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    pop rsi\n"             out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL3 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    pop rsi\n"             out-fd @64 fputs
            "    pop rdx\n"             out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL4 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    pop rsi\n"             out-fd @64 fputs
            "    pop rdx\n"             out-fd @64 fputs
            "    pop r10\n"             out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL5 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    pop rsi\n"             out-fd @64 fputs
            "    pop rdx\n"             out-fd @64 fputs
            "    pop r10\n"             out-fd @64 fputs
            "    pop r8\n"              out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else dup INTRINSIC_SYSCALL6 = if*
            "    pop rax\n"             out-fd @64 fputs
            "    pop rdi\n"             out-fd @64 fputs
            "    pop rsi\n"             out-fd @64 fputs
            "    pop rdx\n"             out-fd @64 fputs
            "    pop r10\n"             out-fd @64 fputs
            "    pop r8\n"              out-fd @64 fputs
            "    pop r9\n"              out-fd @64 fputs
            "    syscall\n"             out-fd @64 fputs
            "    push rax\n"            out-fd @64 fputs
        else
          here eputs ": unreachable.\n" eputs
          1 exit
        end
        end
        drop
    else
      here eputs ": unreachable.\n" eputs
      1 exit
    end

    drop

    1 +
  end drop

  "addr_"    out-fd @64 fputs
  ops-count @64 out-fd @64 fputu
  ":\n"      out-fd @64 fputs

  "    mov rax, 60\n"        out-fd @64 fputs
  "    mov rdi, 0\n"         out-fd @64 fputs
  "    syscall\n"            out-fd @64 fputs
  "segment .data\n"          out-fd @64 fputs
  0 while dup strlits-count @64 < do
    "str_"                           out-fd @64 fputs
    dup                              out-fd @64 fputu
    ": db "                          out-fd @64 fputs
    dup sizeof(Str) * strlits + @Str out-fd @64 fputdecstr
    "\n"                             out-fd @64 fputs
    1 +
  end drop
  "segment .bss\n"           out-fd @64 fputs
  "args_ptr: resq 1\n"       out-fd @64 fputs
  "ret_stack_rsp: resq 1\n"  out-fd @64 fputs
  "ret_stack: resb "         out-fd @64 fputs X86_64_RET_STACK_CAP out-fd @64 fputu "\n" out-fd @64 fputs
  "ret_stack_end:\n"         out-fd @64 fputs
  "mem: resb "               out-fd @64 fputs
  global-memory-capacity @64 out-fd @64 fputu
  "\n"                       out-fd @64 fputs

  out-fd @64 close drop

end

// TODO: implement reusable stack data structure
const SIM_STACK_CAP 1024 end
memory sim-stack-count sizeof(u64) end
memory m4_ifdef([<USE_TLSF>],sim-stack-,sim-stack) m4_ifdef([<USE_TLSF>],sizeof(ptr),sizeof(u64) SIM_STACK_CAP *) end
m4_ifdef([<USE_TLSF>],
proc sim-stack sim-stack- @ptr end
sim-stack-count sizeof(u64) * malloc sim-stack- !ptr
)

proc sim-stack-push int in
  sim-stack-count @64 SIM_STACK_CAP >= if
    here eputs ": ERROR: data stack overflow in simulation mode\n" eputs 1 exit
  end
  sim-stack sim-stack-count @64 8 * + !64
  sim-stack-count inc64
end

proc sim-stack-pop -- int in
  sim-stack-count @64 0 = if
    here eputs ": ERROR: data stack underflow in simulation mode\n" eputs 1 exit
  end
  sim-stack-count dec64
  sim-stack sim-stack-count @64 8 * + @64
end

proc simulate-ops in
  memory sim-ip sizeof(u64) end
  memory sim-op sizeof(Op) end

  0 sim-ip !64
  while sim-ip @64 ops-count @64 < do
    sizeof(Op)
    sim-ip @64 sizeof(Op) * ops +
    sim-op
    memcpy
    drop

    assert "Exhaustive handling of Op types in simulate-ops" COUNT_OPS 16 = end

    sim-op Op.type + @64 OP_PUSH_INT = if
       sim-op Op.operand + @64 sim-stack-push
       sim-ip inc64
    else sim-op Op.type + @64 OP_PUSH_LOCAL_MEM = if*
      here eputs ": TODO: OP_PUSH_LOCAL_MEM is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_PUSH_GLOBAL_MEM = if*
      here eputs ": TODO: OP_PUSH_GLOBAL_MEM is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_PUSH_STR = if*
      here eputs ": TODO: OP_PUSH_STR is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_PUSH_CSTR = if*
      here eputs ": TODO: OP_PUSH_CSTR is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_IF = if*
       sim-stack-pop cast(bool) if
         sim-ip inc64
       else
         sim-op Op.operand + @64 sim-ip !64
       end
    else sim-op Op.type + @64 OP_IFSTAR = if*
      here eputs ": TODO: OP_IFSTAR is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_ELSE = if*
      sim-op Op.operand + @64 sim-ip !64
    else sim-op Op.type + @64 OP_END = if*
      sim-op Op.operand + @64 sim-ip !64
    else sim-op Op.type + @64 OP_WHILE = if*
      sim-ip inc64
      // NOTE: nothing to simulate. `while` is basically a label
    else sim-op Op.type + @64 OP_DO = if*
      sim-stack-pop cast(bool) if
        sim-ip inc64
      else
        sim-op Op.operand + @64 sim-ip !64
      end
    else sim-op Op.type + @64 OP_SKIP_PROC = if*
      sim-op Op.operand + @64 sim-ip !64
    else sim-op Op.type + @64 OP_PREP_PROC = if*
      here eputs ": TODO: OP_PREP_PROC is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_RET = if*
      here eputs ": TODO: OP_RET is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_CALL = if*
      here eputs ": TODO: OP_CALL is not implemented yet in simulation mode\n" eputs
      sim-op Op.token + Token.loc + located-here
      1 exit
    else sim-op Op.type + @64 OP_INTRINSIC = if*
      assert "Exhaustive handling of Intrinsics in generate-nasm-linux-x86_64"
        COUNT_INTRINSICS 43 =
      end

      sim-op Op.operand + @64 INTRINSIC_PLUS = if
        sim-stack-pop
        sim-stack-pop
        +
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_MINUS = if*
        sim-stack-pop
        sim-stack-pop
        swap
        -
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_MUL = if*
        sim-stack-pop
        sim-stack-pop
        *
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_DIVMOD = if*
        sim-stack-pop
        sim-stack-pop
        swap
        divmod
        swap
        sim-stack-push
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_MAX = if*
        here eputs ": TODO: intrinsic `max` is not implemented in simulation mode\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SHR = if*
        sim-stack-pop
        sim-stack-pop
        swap
        shr
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_SHL = if*
        sim-stack-pop
        sim-stack-pop
        swap
        shl
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_OR = if*
        sim-stack-pop
        sim-stack-pop
        or
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_AND = if*
        sim-stack-pop
        sim-stack-pop
        and
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_NOT = if*
        sim-stack-pop
        not
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_PRINT = if*
        sim-stack-pop
        print
      else sim-op Op.operand + @64 INTRINSIC_EQ = if*
        sim-stack-pop
        sim-stack-pop
        =
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_GT = if*
        sim-stack-pop
        sim-stack-pop
        swap
        >
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_LT = if*
        sim-stack-pop
        sim-stack-pop
        swap
        <
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_GE = if*
        sim-stack-pop
        sim-stack-pop
        swap
        >=
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_LE = if*
        sim-stack-pop
        sim-stack-pop
        swap
        <=
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_NE = if*
        sim-stack-pop
        sim-stack-pop
        !=
        cast(int)
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_DUP = if*
        sim-stack-pop
        dup
        sim-stack-push
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_SWAP = if*
        sim-stack-pop
        sim-stack-pop
        swap
        sim-stack-push
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_DROP = if*
        sim-stack-pop
        drop
      else sim-op Op.operand + @64 INTRINSIC_OVER = if*
        sim-stack-pop
        sim-stack-pop
        dup
        sim-stack-push
        swap
        sim-stack-push
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_ROT = if*
        sim-stack-pop
        sim-stack-pop
        sim-stack-pop
        swap
        sim-stack-push
        swap
        sim-stack-push
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_LOAD8 = if*
        here eputs ": TODO: `@8` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_STORE8 = if*
        here eputs ": TODO: `!8` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_LOAD16 = if*
        here eputs ": TODO: `@16` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_STORE16 = if*
        here eputs ": TODO: `!16` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_LOAD32 = if*
        here eputs ": TODO: `@32` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_STORE32 = if*
        here eputs ": TODO: `!32` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_LOAD64 = if*
        here eputs ": TODO: `@64` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_STORE64 = if*
        here eputs ": TODO: `!64` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_ARGC = if*
        here eputs ": TODO: `argc` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_ARGV = if*
        here eputs ": TODO: `argv` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_ENVP = if*
        here eputs ": TODO: `envp` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_CAST_PTR = if*
      else sim-op Op.operand + @64 INTRINSIC_CAST_INT = if*
      else sim-op Op.operand + @64 INTRINSIC_CAST_BOOL = if*
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL0 = if*
        sim-stack-pop
        syscall0
        sim-stack-push
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL1 = if*
        here eputs ": TODO: `syscall1` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL2 = if*
        here eputs ": TODO: `syscall2` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL3 = if*
        here eputs ": TODO: `syscall3` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL4 = if*
        here eputs ": TODO: `syscall4` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL5 = if*
        here eputs ": TODO: `syscall5` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else sim-op Op.operand + @64 INTRINSIC_SYSCALL6 = if*
        here eputs ": TODO: `syscall6` is not implemented yet\n" eputs
        sim-op Op.token + Token.loc + located-here
        1 exit
      else
        here eputs ": unreachable.\n" eputs
        1 exit
      end

      sim-ip inc64
    else
       here eputs ": unreachable\n" eputs 1 exit
    end
  end
end

const PARSE_BLOCK_STACK_CAP 1024 end
memory parse-block-stack-count sizeof(u64) end
memory parse-block-stack sizeof(u64) PARSE_BLOCK_STACK_CAP * end

proc parse-block-stack-push int in
  parse-block-stack-count @64 PARSE_BLOCK_STACK_CAP >= if
    here eputs ": ERROR: parse block stack overflow\n" eputs 1 exit
  end
  parse-block-stack parse-block-stack-count @64 sizeof(u64) * + !64
  parse-block-stack-count inc64
end

proc parse-block-stack-pop -- int in
  parse-block-stack-count @64 0 = if
    here eputs ": ERROR: parse block stack underflow\n" eputs 1 exit
  end
  parse-block-stack-count dec64
  parse-block-stack parse-block-stack-count @64 sizeof(u64) * + @64
end

proc parse-block-stack-top -- int bool in
  parse-block-stack-count @64 0 = if
    0 false
  else
    parse-block-stack parse-block-stack-count @64 1 - sizeof(u64) * + @64
    true
  end
end

const Lexer.content    sizeof(Str) offset end
const Lexer.line       sizeof(Str) offset end
const Lexer.line-start sizeof(ptr) offset end
const Lexer.file-path  sizeof(Str) offset end
const Lexer.row        sizeof(u64) offset end
const sizeof(Lexer) reset end

proc lexer-next-line ptr in
  memory lexer sizeof(ptr) end
  lexer !64

  '\n'
  lexer @ptr Lexer.line +
  lexer @ptr Lexer.content +
  str-chop-by-delim

  lexer @ptr Lexer.line + offsetof(Str.data) + @ptr
  lexer @ptr Lexer.line-start +
  !64

  lexer @ptr Lexer.row + inc64
end

proc lexer-loc
  ptr // loc
  ptr // lexer
in
  memory lexer sizeof(ptr) end
  lexer !ptr
  memory loc sizeof(ptr) end
  loc !ptr

  // File Path
  sizeof(Str)
  lexer @ptr Lexer.file-path +
  loc   @ptr Loc.file-path   +
  memcpy
  drop

  // Row
  lexer @ptr Lexer.row + @int
  loc   @ptr Loc.row   + !int

  // Column
  lexer @ptr Lexer.line + offsetof(Str.data) + @ptr
  lexer @ptr Lexer.line-start + @ptr
  -
  1 +
  loc @ptr Loc.col +
  !int
end

proc lexer-consume-strlit
  ptr // lexer
  --
  int ptr // string literal
in
  memory lexer sizeof(ptr) end
  lexer !ptr

  memory start sizeof(ptr) end
  strbuf-end start !ptr

  memory count sizeof(int) end
  0 count !int

  memory loc sizeof(Loc) end

  lexer @ptr Lexer.line +
    while
      dup ?str-empty lnot if
        dup @Str.data @8 '"' = if
          dup str-chop-one-left
          false
        else dup @Str.data @8 '\\' = if*
          dup str-chop-one-left

          dup ?str-empty if
            loc lexer @ptr lexer-loc
            loc eputloc ": ERROR: unfinished escape sequence\n" eputs
            1 exit
          end

          dup @Str.data @8 'n' = if
            10 strbuf-append-char
            dup str-chop-one-left
            count inc64
            true
          else dup @Str.data @8 '\\' = if*
            92 strbuf-append-char
            dup str-chop-one-left
            count inc64
            true
          else dup @Str.data @8 '\"' = if*
            34 strbuf-append-char
            dup str-chop-one-left
            count inc64
            true
          else
            loc lexer @ptr lexer-loc
            loc eputloc ": ERROR: unknown escape character `" eputs 1 over @Str.data eputs "`\n" eputs
            1 exit
            false
          end
        else
          dup @Str.data @8 strbuf-append-char
          dup str-chop-one-left
          count inc64
          true
        end
      else false end
    do end
  drop

  count @int start @ptr
  // TODO: check if the string literal was actually closed at the end
end

proc lexer-next-token
  ptr // token
  ptr // lexer
  --
  bool
in
  memory lexer sizeof(ptr) end
  lexer !64
  memory token sizeof(ptr) end
  token !64

  memory word sizeof(Str) end

  lexer @ptr
  while
    dup Lexer.line + str-trim-left

    dup Lexer.line + ?str-empty if
      dup Lexer.content + ?str-empty lnot
    else
      dup Lexer.line +
      "//" rot @Str str-starts-with
    end
  do dup lexer-next-line end

  dup Lexer.line + ?str-empty lnot if
    token @ptr Token.loc +
    lexer @ptr
    lexer-loc

    dup Lexer.line + @Str.data @8 '"' = if
       // String literal
       dup Lexer.line + str-chop-one-left
       lexer-consume-strlit word !Str
       word @Str token @ptr Token.value + !Str

       lexer @ptr Lexer.line + ?str-empty lnot if
         lexer @ptr Lexer.line + @Str.data @8 'c' = if
           lexer @ptr Lexer.line + str-chop-one-left
           0 strbuf-append-char
           token @ptr Token.value + offsetof(Str.count) + inc64
           TOKEN_CSTR token @ptr Token.type + !64
         else
           TOKEN_STR token @ptr Token.type + !64
         end
       else
         TOKEN_STR token @ptr Token.type + !64
       end
    else dup Lexer.line + @Str.data @8 39 = if* // TODO: can't use ' directly for some reason
       // Character literal
       dup Lexer.line + str-chop-one-left
       39 word rot Lexer.line + str-chop-by-delim

       word @Str "\\n" streq if
         10 token @ptr Token.value + !int
       else word @Str "\\\\" streq if*
         92 token @ptr Token.value + !int
       else word @Str "\\\"" streq if*
         34 token @ptr Token.value + !int
       else word @Str.count 1 = if*
         word @Str.data @8 token @ptr Token.value + !int
       else
         token @ptr Token.loc + eputloc ": only a single byte is allowed inside of a character literal\n" eputs
         1 exit
       end

       TOKEN_CHAR token @ptr Token.type + !64

       // TODO: check if the character literal was actually closed at the end
       // TODO: character literals don't support escaping
    else
       // Word or integer literal

       ' '               // delim
       word              // word
       rot Lexer.line +  // line
       str-chop-by-delim

       word @Str try-parse-int if
          token @ptr Token.value + !64
          TOKEN_INT token @ptr Token.type  + !64
       else
          drop // number from try-parse-int
          word @Str  token @ptr Token.value + !Str
          TOKEN_WORD token @ptr Token.type + !64
       end
    end

    word @Str token @ptr Token.text + !Str

    true
  else
    drop // lexer
    false
  end
end

const ConstFrame.type sizeof(u64) offset end
const ConstFrame.value sizeof(u64) offset end
const sizeof(ConstFrame) reset end

const CONST_STACK_CAP 1024 end
memory const-stack-count sizeof(u64) end
memory const-stack sizeof(ConstFrame) CONST_STACK_CAP * end
memory iota sizeof(int) end

proc const-stack-clean in
  0 const-stack-count !64
end

proc const-stack-push
  int // type
  int // value
in
  memory frame sizeof(ConstFrame) end
  frame ConstFrame.value + !64
  frame ConstFrame.type + !64

  sizeof(ConstFrame) frame CONST_STACK_CAP const-stack const-stack-count append-item lnot if
    here eputs ": TODO: const stack overflow\n" eputs
    1 exit
  end
  drop
end

proc const-stack-pop
  --
  int // type
  int // value
in
  const-stack-count @64 0 <= if
    here eputs ": TODO: const stack underflow\n" eputs
    1 exit
  end

  const-stack-count dec64
  const-stack-count @64 sizeof(ConstFrame) * const-stack +
  dup ConstFrame.type + @64
  swap ConstFrame.value + @64
end

const DATATYPE_INT  1 offset end
const DATATYPE_PTR  1 offset end
const DATATYPE_BOOL 1 offset end
const COUNT_DATATYPES  reset end

const HUMAN_SINGULAR 1 offset end
const HUMAN_PLURAL   1 offset end
const COUNT_HUMAN       reset end


proc human-token-type
  int // token type
  int // plurality
  --
  int ptr // str
in
  assert "Exhaustive handling of noun categories" COUNT_HUMAN 2 = end

  dup HUMAN_SINGULAR = if
    drop
    assert "Exhaustive handling of token types" COUNT_TOKENS 5 = end
    dup TOKEN_INT = if
      drop
      "an integer"
    else dup TOKEN_WORD = if*
      drop
      "a word"
    else dup TOKEN_STR = if*
      drop
      "a string"
    else dup TOKEN_CSTR = if*
      drop
      "a C-style string"
    else dup TOKEN_CHAR = if*
      drop
      "a character"
    else
      drop
      here eputs ": unreachable\n" eputs
      0 NULL
    end
  else dup HUMAN_PLURAL = if*
    drop
    assert "Exhaustive handling of token types" COUNT_TOKENS 5 = end
    dup TOKEN_INT = if
      drop
      "integers"
    else dup TOKEN_WORD = if*
      drop
      "words"
    else dup TOKEN_STR = if*
      drop
      "strings"
    else dup TOKEN_CSTR = if*
      drop
      "C-style strings"
    else dup TOKEN_CHAR = if*
      drop
      "characters"
    else
      drop
      here eputs ": unreachable\n" eputs
      69 exit
      0 NULL
    end
  else
    2drop
    here eputs ": unreachable\n" eputs
    69 exit
    0 NULL
  end
end

proc eval-const-value
  ptr // ptr to lexer
  --
  int // type
  int // value
in
  memory token sizeof(Token) end
  memory done sizeof(bool) end
  false done !64

  const-stack-clean

  while
    done @bool lnot if
      token over lexer-next-token
    else false end
  do
    token Token.type + @64 TOKEN_INT = if
      DATATYPE_INT token Token.value + @64 const-stack-push
    else token Token.type + @64 TOKEN_WORD = if*
      token Token.value + @Str intrinsic-by-name if
        dup INTRINSIC_CAST_PTR = if
          const-stack-pop
          swap drop
          DATATYPE_PTR swap
          const-stack-push
        else dup INTRINSIC_CAST_BOOL = if*
          const-stack-pop
          swap drop
          DATATYPE_BOOL swap
          const-stack-push
        else dup INTRINSIC_MINUS = if*
          // TODO: `-` intrinsic ignores the types in compile time evaluation
          const-stack-pop swap drop
          const-stack-pop swap drop
          swap
          -
          DATATYPE_INT swap const-stack-push
        else dup INTRINSIC_PLUS = if*
          // TODO: `+` intrinsic ignores the types in compile time evaluation
          const-stack-pop swap drop
          const-stack-pop swap drop
          swap
          +
          DATATYPE_INT swap const-stack-push
        else dup INTRINSIC_MUL = if*
          // TODO: `*` intrinsic ignores the types in compile time evaluation
          const-stack-pop swap drop
          const-stack-pop swap drop
          swap
          *
          DATATYPE_INT swap const-stack-push
        else dup INTRINSIC_EQ = if*
          // TODO: `=` intrinsic ignores the types in compile time evaluation
          const-stack-pop swap drop
          const-stack-pop swap drop
          swap
          = cast(int)
          DATATYPE_BOOL swap const-stack-push
        else dup INTRINSIC_MAX = if*
          // TODO: `max` intrinsic ignores the types in compile time evaluation
          const-stack-pop swap drop
          const-stack-pop swap drop
          swap
          max
          DATATYPE_INT swap const-stack-push
        else
          token Token.loc + eputloc ": ERROR: intrinsic `" eputs token Token.value + @Str eputs "` is not supported in compile time evaluation\n" eputs
          1 exit
        end
      else token Token.value + @Str "end" streq if*
        true done !64
      else token Token.value + @Str "offset" streq if*
        const-stack-pop swap drop // TODO: offset ignores the type
        DATATYPE_INT iota @int const-stack-push
        iota @int + iota !int
      else token Token.value + @Str "reset" streq if*
        DATATYPE_INT iota @int const-stack-push
        0 iota !int
      else token Token.value + @Str const-lookup dup NULL != if*
        dup Const.type + @64
        swap Const.value + @64
        const-stack-push
      else token Token.value + @Str try-parse-int if*
        DATATYPE_PTR swap const-stack-push
        drop // const
      else
        drop // try-parse-int
        drop // const
        token Token.loc + eputloc ": ERROR: only intrinsic words are allowed in compile time evaluation\n" eputs
        token Token.loc + eputloc ": NOTE: intrinsic `" eputs token Token.value + @Str eputs "` does not exist\n" eputs
        1 exit
      end
      drop // intrinsic
    else
      token Token.loc + eputloc
      ": ERROR: " eputs
      token Token.type + @64 HUMAN_PLURAL human-token-type eputs
      " are not supported in compile time evaluation\n" eputs
      1 exit
    end
  end drop

  done @bool if
    const-stack-count @64 1 != if
      token Token.loc + eputloc
      ": ERROR: The result of expression in compile time evaluation must be a single number\n" eputs
      1 exit
    end

    const-stack-pop
  else
    here eputs ": TODO: const expression was not closed properly\n" eputs
    1 exit
    0 0
  end
end

proc map-file
  ptr // file-path-cstr
  --
  int ptr
in
  memory file-path-cstr sizeof(ptr) end
  file-path-cstr !64

  0                   // mode
  O_RDONLY            // flags
  file-path-cstr @ptr // pathname
  // TODO: this is lame, let's just support negative numbers properly
  0 100 - // AT_FDCWD            // dirfd
  openat

  dup 0 < if
    "ERROR: could not open file " eputs file-path-cstr @ptr cstr-to-str eputs "\n" eputs
    1 exit
  end

  memory fd sizeof(u64) end
  fd !64

  memory statbuf sizeof(stat) end
  statbuf fd @64 fstat 0 < if
    "ERROR: could not determine the size of file " eputs file-path-cstr @ptr cstr-to-str eputs "\n" eputs
    1 exit
  end

  memory content sizeof(Str) end
  statbuf @stat.st_size content !Str.count

  0                        // offset
  fd @64                   // fd
  MAP_PRIVATE              // flags
  PROT_READ                // prot
  content @Str.count       // length
  m4_ifdef([<USE_TLSF>],statbuf @stat.st_size malloc,NULL)// addr
  mmap
  cast(ptr)
  content !Str.data

  content @Str.data cast(int) 0 < if
    "ERROR: could not memory map file " eputs file-path-cstr @ptr cstr-to-str eputs "\n" eputs
    1 exit
  end

  content @Str
end

proc lex-file ptr in
  memory file-path-cstr sizeof(ptr) end
  file-path-cstr !64

  memory lexer sizeof(Lexer) end
  sizeof(Lexer) 0 lexer memset drop
  file-path-cstr @ptr map-file    lexer Lexer.content   + !Str
  file-path-cstr @ptr cstr-to-str lexer Lexer.file-path + !Str

  memory token sizeof(Token) end

  while token lexer lexer-next-token do

    assert "Exhaustive handling of token types in lex-file" COUNT_TOKENS 5 = end

    token Token.loc + // loc
    dup Loc.file-path + @Str puts ":" puts
    dup Loc.row + @64 putu        ":" puts
    dup Loc.col + @64 putu        ": " puts
    drop // loc

    token Token.type + @64 // token.type
    dup TOKEN_INT = if
      "[INTEGER] " puts token Token.value + @int putu "\n" puts
    else dup TOKEN_WORD = if*
      "[WORD] " puts token Token.value + @Str puts "\n" puts
    else dup TOKEN_STR = if*
      "[STR] \"" puts token Token.value + @Str puts "\"\n" puts
    else dup TOKEN_CSTR = if*
      "[CSTR] \"" puts token Token.value + @Str puts "\"\n" puts
    else dup TOKEN_CHAR = if*
      "[CHAR] " puts token Token.value + @int putu "\n" puts
    else
      here eputs ": Unreachable. Unknown token type.\n" eputs
      1 exit
    end

    drop // token.type
  end
end

proc local-memories-clean in
  0 local-memories-count !64
  0 local-memory-capacity !64
end

proc local-memories-lookup
  int ptr // name
  --
  ptr     // Memory
in
  memory name sizeof(Str) end
  name !Str

  0 while
    dup local-memories-count @64 < if
      dup sizeof(Memory) * local-memories + Memory.name + @Str
      name @Str
      streq
      lnot
    else false end
  do 1 + end

  dup local-memories-count @64 < if
    sizeof(Memory) * local-memories +
  else
    drop NULL
  end
end

proc global-memories-lookup
  int ptr // name
  --
  ptr     // Memory
in
  memory name sizeof(Str) end
  name !Str

  0 while
    dup global-memories-count @64 < if
      dup sizeof(Memory) * global-memories + Memory.name + @Str
      name @Str
      streq
      lnot
    else false end
  do 1 + end

  dup global-memories-count @64 < if
    sizeof(Memory) * global-memories +
  else
    drop NULL
  end
end

proc local-memory-define
  ptr
in
  sizeof(Memory) swap LOCAL_MEMORIES_CAP local-memories local-memories-count append-item lnot if
    here eputs ": ERROR: local memory definitions capacity exceeded\n" eputs
    1 exit
  end
  drop
end

proc global-memory-define
  ptr
in
  sizeof(Memory) swap GLOBAL_MEMORIES_CAP global-memories global-memories-count append-item lnot if
    here eputs ": ERROR: global memory definitions capacity exceeded\n" eputs
    1 exit
  end
  drop
end

proc check-name-redefinition
  int ptr // name
  ptr     // loc
in
  memory loc sizeof(Loc) end
  sizeof(Loc) swap loc memcpy drop
  memory name sizeof(Str) end
  name !Str

  name @Str const-lookup dup NULL != if
    loc eputloc ": ERROR: redefinition of a constant `" eputs name @Str eputs "`\n" eputs
    dup Const.loc + eputloc ": NOTE: the original definition is located here\n" eputs
    1 exit
  end drop

  name @Str proc-lookup dup NULL != if
    loc eputloc ": ERROR: redefinition of a procedure `" eputs name @Str eputs "`\n" eputs
    dup Proc.loc + eputloc ": NOTE: the original definition is located here\n" eputs
    1 exit
  end drop

  name @Str local-memories-lookup dup NULL != if
    loc eputloc ": ERROR: redefinition of local memory `" eputs name @Str eputs "`\n" eputs
    dup Memory.loc + eputloc ": NOTE: the original definition is located here\n" eputs
    1 exit
  end drop

  inside-proc @bool lnot if
    name @Str global-memories-lookup dup NULL != if
      loc eputloc ": ERROR: redefinition of global memory `" eputs name @Str eputs "`\n" eputs
      dup Memory.loc + eputloc ": NOTE: the original definition is located here\n" eputs
      1 exit
    end drop
  end
end

proc datatype-by-name
  int ptr // data type name
  --
  int // data type
  bool // found
in
  memory name sizeof(Str) end
  name !Str
  assert "Exhaustive handling of data types in datatype-by-name" COUNT_DATATYPES 3 = end
       name @Str "ptr"  streq if  DATATYPE_PTR  true
  else name @Str "bool" streq if* DATATYPE_BOOL true
  else name @Str "int"  streq if* DATATYPE_INT  true
  else 0 false end
end

proc skip-proc-contract
  ptr // lexer
in
  memory token sizeof(Token) end
  memory ended-with-in sizeof(bool) end

  false ended-with-in !bool

  while
    token over lexer-next-token if
      token Token.type + @64 TOKEN_WORD = if
        token Token.value + @Str "in" streq
        ended-with-in !bool
        ended-with-in @bool lnot
      else token Token.type + @64 TOKEN_STR = if*
        true
      else
        here eputs ": TODO: report unsupported token type in proc definition \n" eputs
        token Token.loc + eputloc ": located in here\n" eputs
        1 exit
        false
      end
    else false end
  do end
  drop

  ended-with-in @bool lnot if
    here eputs ": TODO: report tokens ended before `in` \n" eputs
    1 exit
  end
end

proc enclose-while-do
  int // do-ip
  ptr // token
in
  memory token sizeof(Token) end
  sizeof(Token) swap token memcpy drop

  memory do-ip sizeof(int) end
  do-ip !int

  memory do-op sizeof(ptr) end
  do-ip @int sizeof(Op) * ops + do-op !ptr

  memory while-ip sizeof(int) end
  do-op @ptr Op.operand + @int while-ip !int

  while-ip @int ops-count @int >= if
    here eputs ": Assertion Failed: out of range\n" eputs
    1 exit
  end

  memory while-op sizeof(ptr) end
  while-ip @int sizeof(Op) * ops + while-op !ptr

  while-op @ptr Op.type + @int OP_WHILE != if
    here eputs ": Assertion Failed: `do` does not precede `while`\n" eputs
    1 exit
  end

  OP_END while-ip @int token push-op
  ops-count @int do-op @ptr Op.operand + !int
end

proc chain-else-if*
  int // if*-ip
  ptr // token
in
  memory token sizeof(Token) end
  sizeof(Token) swap token memcpy drop

  memory ifstar-ip sizeof(int) end
  ifstar-ip !int

  memory ifstar-op sizeof(ptr) end
  ifstar-ip @int sizeof(Op) * ops + ifstar-op !ptr

  ifstar-op @ptr Op.type + @int OP_IFSTAR != if
    here eputs ": Assertion Failed: expected `if*`\n" eputs
    1 exit
  end

  memory else-ip sizeof(int) end
  parse-block-stack-pop else-ip !int

  memory else-op sizeof(ptr) end
  else-ip @int sizeof(Op) * ops + else-op !ptr

  ops-count @int 1 +
  ifstar-op @ptr Op.operand +
  !int

  ops-count @int
  else-op @ptr Op.operand +
  !int

  ops-count @int
  parse-block-stack-push

  OP_ELSE
  0
  token
  push-op
end

proc compile-file-into-ops ptr in
  memory file-path-cstr sizeof(ptr) end
  file-path-cstr !64

  memory lexer sizeof(Lexer) end
  sizeof(Lexer) 0 lexer memset drop
  file-path-cstr @ptr map-file    lexer Lexer.content   + !Str
  file-path-cstr @ptr cstr-to-str lexer Lexer.file-path + !Str

  memory token sizeof(Token) end
  memory konst sizeof(Const) end
  memory prok sizeof(Proc) end
  memory memori sizeof(Memory) end

  false inside-proc !64

  while token lexer lexer-next-token do
    assert "Exhaustive handling of Token types" COUNT_TOKENS 5 = end

    token Token.type + @64 // token.type

    dup TOKEN_INT = if
      OP_PUSH_INT
      token Token.value + @64
      token
      push-op
    else dup TOKEN_WORD = if*
      token Token.value + // token.value

      assert "Exhaustive handling of Op types in parse-file-path" COUNT_OPS 16 = end

      dup @Str intrinsic-by-name if
        OP_INTRINSIC swap token push-op
      else
        drop
        dup @Str "if" streq if
          ops-count @64 parse-block-stack-push
          OP_IF 0 token push-op
        else dup @Str "extern" if*
          memory x sizeof(Token) end
          x lexer lexer-next-token
          Op.EXTERN OP_RET x Token.value + x push-op-f
        else dup @Str "call-extern" if*
          memory x sizeof(Token) end
          x lexer lexer-next-token
          Op.EXTERN OP_CALL x Token.value + x push-op-f
        else dup @Str "call-extern-raw" if*
          memory x sizeof(Token) end
          x lexer lexer-next-token
          Op.EXTERN Op.RAW or OP_CALL x Token.value + x push-op-f
        else dup @Str "if*" streq if*
          parse-block-stack-top lnot if
            token Token.loc + eputloc ": ERROR: `if*` can only come after `else`, but found nothing\n" eputs
            1 exit
          end

          sizeof(Op) * ops +

          dup Op.type + @int OP_ELSE != if
            token Token.loc + eputloc ": ERROR: `if*` can only come after `else`\n" eputs
            1 exit
          end

          drop

          ops-count @64 parse-block-stack-push
          OP_IFSTAR 0 token push-op
        else dup @Str "else" streq if*
          parse-block-stack-count @64 0 <= if
            token Token.loc + eputloc
            ": ERROR: `else` can only come after `if` or `if*`\n" eputs
            1 exit
          end

          parse-block-stack-pop   // if_ip
          dup sizeof(Op) * ops +  // if_op

          dup Op.type + @64 OP_IF = if
            ops-count @64 1 + over Op.operand + !64

            ops-count @64 parse-block-stack-push
            OP_ELSE 0 token push-op
          else dup Op.type + @64 OP_IFSTAR = if*
            over token chain-else-if*
          else
            token Token.loc + eputloc
            ": ERROR: `else` can only come after `if` or `if*`\n" eputs
            1 exit
          end

          drop // if_op
          drop // if_ip
        else dup @Str "while" streq if*
          ops-count @64 parse-block-stack-push
          OP_WHILE 0 token push-op
        else dup @Str "do" streq if*
          parse-block-stack-count @64 0 <= if
            token Token.loc + eputloc ": ERROR: `do` is not preceded by `while`\n" eputs
            1 exit
          end

          parse-block-stack-pop  // ip
          dup sizeof(Op) * ops + // op

          dup Op.type + @64 OP_WHILE != if
            token Token.loc + eputloc ": ERROR: `do` is not preceded by `while`\n" eputs
            dup Op.token + Token.loc + eputloc ": NOTE: preceded by `" eputs dup Op.token + Token.text + @Str eputs "` instead\n" eputs
            1 exit
          end

          swap

          ops-count @64 parse-block-stack-push

          OP_DO swap token push-op
          drop // op
        else dup @Str "end" streq if*
          parse-block-stack-count @64 0 <= if
            token Token.loc + eputloc
            ": ERROR: `end` has nothing to close\n" eputs
            1 exit
          end

          parse-block-stack-pop   // ip
          ops over sizeof(Op) * + // op

          dup Op.type + @64 OP_IF = if
            dup ops-count @64 swap Op.operand + !64
            OP_END ops-count @64 1 + token push-op
          else dup Op.type + @64 OP_ELSE = if*
            dup ops-count @64 swap Op.operand + !64
            OP_END ops-count @64 1 + token push-op
          else dup Op.type + @64 OP_DO = if*
            over token enclose-while-do
          else dup Op.type + @64 OP_PREP_PROC = if*
            local-memory-capacity @64
            over Op.operand +
            !64

            inside-proc @bool lnot if
              here eputs ": Assertion failed: OP_PREP_PROC outside of actual proc\n" eputs
              1 exit
            end

            parse-block-stack-pop
            sizeof(Op) *
            ops +

            dup Op.type + @64 OP_SKIP_PROC != if
              here eputs ": Assertion failed: Expected OP_SKIP_PROC before OP_PREP_PROC\n" eputs
              1 exit
            end

            OP_RET
            local-memory-capacity @64
            token
            push-op

            Op.operand + ops-count @64 swap !64

            local-memories-clean
            false inside-proc !bool
          else dup Op.type + @64 OP_SKIP_PROC = if*
            here eputs ": unreachable\n" eputs
            1 exit
          else
            token Token.loc + eputloc ": ERROR: `end` can only close `if` or `else` for now\n" eputs
            dup Op.token + Token.loc + eputloc ": NOTE: found `" eputs dup Op.token + Token.text + @Str eputs "` instead\n" eputs
            1 exit
          end

          drop // op
          drop // ip
        else dup @Str "include" streq if*
          token lexer lexer-next-token lnot if
            token Token.loc + eputloc
            ": expected path to the include file but found nothing\n" eputs
            1 exit
          end

          token Token.type + @64 TOKEN_STR != if
            token Token.loc + eputloc
            // TODO: report what was found instead of a string
            ": expected path to the include file to be a string\n" eputs
            1 exit
          end

          // TODO: introduce include limit
          token Token.value + @Str tmp-str-to-cstr compile-file-into-ops
        else dup @Str "const" streq if*
          token lexer lexer-next-token lnot if
            token Token.loc + eputloc
            ": expected constant name but found nothing\n" eputs
            1 exit
          end

          token Token.type + @64 TOKEN_WORD != if
            token Token.loc + eputloc
            // TODO: report what was found instead of a word
            ": expected constant name to be a word\n" eputs
            1 exit
          end

          token Token.value + @Str
          token Token.loc +
          check-name-redefinition

          token Token.value + @Str konst Const.name + !Str
          sizeof(Loc) token Token.loc + konst Const.loc + memcpy drop

          lexer eval-const-value

          konst Const.value + !64
          konst Const.type + !64

          konst const-define
        else dup @Str "proc" streq if*
          inside-proc @bool if
            here eputs ": TODO: reporting proc inside proc error is not implemented yet\n" eputs
            1 exit
          end

          sizeof(Proc) 0 prok memset drop

          sizeof(Loc) token Token.loc + prok Proc.loc + memcpy drop

          token lexer lexer-next-token lnot if
            token Token.loc + eputloc
            ": expected procedure name but found nothing\n" eputs
            1 exit
          end

          token Token.type + @64 TOKEN_WORD != if
            token Token.loc + eputloc
            ": expected procedure name to be a word but found " eputs
            token Token.type + @64 HUMAN_SINGULAR human-token-type eputs
            " instead\n" eputs
            1 exit
          end

          token Token.value + @Str
          token Token.loc +
          check-name-redefinition

          sizeof(Str) token Token.value + prok Proc.name + memcpy drop

          ops-count @64 parse-block-stack-push
          OP_SKIP_PROC 0 token push-op

          ops-count @64
          dup prok Proc.addr + !64
              parse-block-stack-push
          OP_PREP_PROC 0 token push-op

          lexer skip-proc-contract

          true inside-proc !bool

          prok proc-define
        else dup @Str "memory" streq if*
          token lexer lexer-next-token lnot if
            token Token.loc + eputloc
            ": expected memory name but found nothing\n" eputs
            1 exit
          end

          token Token.type + @64 TOKEN_WORD != if
            token Token.loc + eputloc
            ": expected memory name to be a word but found " eputs
            token Token.type + @64 HUMAN_SINGULAR human-token-type eputs
            " instead\n" eputs
            1 exit
          end

          token Token.value + @Str
          token Token.loc +
          check-name-redefinition

          sizeof(Str) token Token.value + memori Memory.name + memcpy drop
          sizeof(Loc) token Token.loc   + memori Memory.loc  + memcpy drop

          lexer eval-const-value

          swap DATATYPE_INT != if
            here eputs ": TODO: memory size must be `int` error\n" eputs 1 exit
          end

          inside-proc @bool if
            local-memory-capacity @64 memori Memory.offset + !64
            local-memory-capacity @64 + local-memory-capacity !64
            memori local-memory-define
          else
            global-memory-capacity @64 memori Memory.offset + !64
            global-memory-capacity @64 + global-memory-capacity !64
            memori global-memory-define
          end
        else dup @Str "assert" streq if*
          token lexer lexer-next-token lnot if
            token Token.loc + eputloc
            ": expected assert message but found nothing\n" eputs
            1 exit
          end

          token Token.type + @64 TOKEN_STR != if
            token Token.loc + eputloc
            // TODO: report what was found instead of a string
            ": expected assert message to be a string\n" eputs
            1 exit
          end

          lexer eval-const-value

          swap DATATYPE_BOOL != if
            token Token.loc + eputloc ": ERROR: assertion expects the expression to be of type `bool`\n" eputs
            1 exit
          end

          cast(bool) lnot if
            token Token.loc + eputloc ": ERROR: Static Assertion Failed: " eputs token Token.value + @Str eputs "\n" eputs
            1 exit
          end
        else dup @Str "here" streq if*
          OP_PUSH_STR
          token Token.loc + strbuf-loc strlit-define
          token
          push-op
        else dup @Str const-lookup dup NULL != if*
          OP_PUSH_INT
          swap Const.value + @64
          token
          push-op
        else drop dup @Str proc-lookup dup NULL != if*
          OP_CALL
          swap Proc.addr + @64
          token
          push-op
        else drop dup @Str local-memories-lookup dup NULL != if*
          OP_PUSH_LOCAL_MEM
          swap Memory.offset + @64
          token
          push-op
        else drop dup @Str global-memories-lookup dup NULL != if*
          OP_PUSH_GLOBAL_MEM
          swap Memory.offset + @64
          token
          push-op
        else drop
          token Token.loc + eputloc
          ": ERROR: unknown word `" puts dup @Str puts "`\n" puts
          1 exit
        end
      end
      drop // token.value
    else dup TOKEN_STR = if*
      OP_PUSH_STR
      token Token.value + @Str strlit-define
      token
      push-op
    else dup TOKEN_CSTR = if*
      OP_PUSH_CSTR
      token Token.value + @Str strlit-define
      token
      push-op
    else dup TOKEN_CHAR = if*
      OP_PUSH_INT
      token Token.value + @int
      token
      push-op
    else
      here eputs ": Unreachable. Unknown token type.\n" eputs
      1 exit
    end

    drop // token.type

  end

  parse-block-stack-count @64 0 > if
    parse-block-stack-pop
    sizeof(Op) *
    ops +

    dup Op.token + Token.loc + eputloc ": unclosed block\n" eputs

    1 exit
    drop
  end

  // TODO: compile-file-into-ops does not clean up resources after itself
end
proc dump-ops-to-ir ptr in
memory out-fd sizeof(u64) end
  memory buf sizeof(u64) end
  420 swap                    // mode
  O_CREAT O_WRONLY or O_TRUNC or swap // flags
  // TODO: the output file path should be based on the input file path
     // pathname
  // TODO: this is lame, let's just support negative numbers properly
  0 100 - //AT_FDCWD
  openat
  8 ops-count out-fd !64 write
  ops-count @64 sizeof(Op) * ops out-fd !64 write
  ops-count @64 while dup 0 > do
  dup sizeof(Op) * ops + dup Op.flags Op.EXTERN and cast(bool) if
  Op.operand @Str Str.count buf !64 8 buf out-fd !64 write
  Op.operand @Str out-fd !64 write
  end
  end
end
proc read-from-ir ptr in
memory out-fd sizeof(u64) end
  memory buf sizeof(u64) end
  420 swap                    // mode
  O_RDWR or O_TRUNC or swap // flags
  // TODO: the output file path should be based on the input file path
     // pathname
  // TODO: this is lame, let's just support negative numbers properly
  0 100 - //AT_FDCWD
  openat
  8 ops-count out-fd !64 read
  ops-count @64 sizeof(Op) * ops out-fd !64 read
  ops-count @64 while dup 0 > do
  dup sizeof(Op) * ops + dup Op.flags Op.EXTERN and cast(bool) if
   8 buf out-fd !64 read
  Op.operand @Str Str.count buf swap !64
  Op.operand @Str out-fd !64 read
  end
  end
end
proc summary in
  // TODO: lexer stats: tokens count, lines count, etc
  "Ops count:                    " puts ops-count @int putu "\n" puts
  "Consts count:                 " puts consts-count @int putu "\n" puts
  "Procs count:                  " puts procs-count @int putu "\n" puts
  "String literals count:        " puts strlits-count @int putu "\n" puts
  "String literals size (bytes): " puts strbuf-size @int putu "\n" puts
  "Global memory size (bytes):   " puts global-memory-capacity @int putu "\n" puts
end

proc usage
  ptr // program name
  int // fd
in
  memory fd sizeof(u64) end
  fd !64

  memory name sizeof(ptr) end
  name !ptr

  "Usage: " eputs name @ptr cstr-to-str puts " <SUBCOMMAND>\n"            fd @64 fputs
  "  SUBCOMMANDS:\n"                                                      fd @64 fputs
  "    sim <file>       Simulate the program.\n"                          fd @64 fputs
  // TODO: -r flag for com subcommand
  "    com <file> [ir]       Compile the program\n"                            fd @64 fputs
  "    dump <file>      Dump the ops of the program\n"                    fd @64 fputs
  "    lex <file>       Produce lexical analysis of the file\n"           fd @64 fputs
  "    summary <file>   Print the summary of the program\n"               fd @64 fputs
  "    help             Print this help to stdout and exit with 0 code\n" fd @64 fputs
end

proc main in
  memory args sizeof(ptr) end
  argv args !ptr

  memory program sizeof(ptr) end
  args @@ptr program !ptr

  args sizeof(ptr) inc64-by
  args @@ptr NULL = if
    program @ptr stderr usage
    "ERROR: subcommand is not provided\n" eputs
    1 exit
  end

  // TODO: porth.porth does not type check compiled program

  args @@ptr "sim"c cstreq if
    args sizeof(ptr) inc64-by
    args @@ptr NULL = if
      program @ptr stderr usage
      "ERROR: no input file is provided for the `sim` subcommand\n" eputs
      1 exit
    end

    args @@ptr compile-file-into-ops

    simulate-ops
  else args @@ptr "com"c cstreq if*
    args sizeof(ptr) inc64-by
    args @@ptr NULL = if
      program @ptr stderr usage
      "ERROR: no input file is provided for the `com` subcommand\n" eputs
      1 exit
    end
    args 8 + @@ptr "-ir" str-to-cstr cstreq if
    args @@ptr read-from-ir
        args 16 + @@ptr compile-file-into-ops
    else
        args @@ptr compile-file-into-ops
    end

args 8 + @@ptr "-gen-ir" str-to-cstr cstreq args 16 + @@ptr "-gen-ir" str-to-cstr cstreq  or if
"./output.porth-ir"c dump-ops-to-ir
else
    X64 generate-nasm-linux-x86_64
        // TODO: implement tmp-rewind for this specific usecase

    tmp-end
    "nasm"c       tmp-append-ptr
    "-felf64"c    tmp-append-ptr
    "output.asm"c tmp-append-ptr
    NULL          tmp-append-ptr
    cmd-echoed

    tmp-end
    "ld"c         tmp-append-ptr
    "-o"c         tmp-append-ptr
    "output"c     tmp-append-ptr
    "output.o"c   tmp-append-ptr
    NULL          tmp-append-ptr
    cmd-echoed

    run @bool if
      tmp-end
      "./output"c tmp-append-ptr
      NULL        tmp-append-ptr
      cmd-echoed
    end
end
  else args @@ptr "help"c cstreq if*
    program @ptr stdout usage
    0 exit
  else args @@ptr "dump"c cstreq if*
    args sizeof(ptr) inc64-by
    args @@ptr NULL = if
      program @ptr stderr usage
      "ERROR: no input file is provided for the `dump` subcommand\n" eputs
      1 exit
    end

    args @@ptr compile-file-into-ops

    dump-ops
  else args @@ptr "lex"c cstreq if*
    args sizeof(ptr) inc64-by
    args @@ptr NULL = if
      program @ptr stderr usage
      "ERROR: no input file is provided for the `lex` subcommand\n" eputs
      1 exit
    end

    args @@ptr lex-file
  else args @@ptr "summary"c cstreq if*
    args sizeof(ptr) inc64-by
    args @@ptr NULL = if
      program @ptr stderr usage
      "ERROR: no input file is provided for the `dump` subcommand\n" eputs
      1 exit
    end

    args @@ptr compile-file-into-ops

    summary
  else
    program @ptr stderr usage
    "ERROR: unknown subcommand `" eputs args @@ptr cstr-to-str eputs "`\n" eputs
    1 exit
  end
end

main
