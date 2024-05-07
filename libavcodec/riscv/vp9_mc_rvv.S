/*
 * Copyright (c) 2024 Institue of Software Chinese Academy of Sciences (ISCAS).
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "libavutil/riscv/asm.S"

.macro vsetvlstatic8 len an maxlen mn=m4
.if \len == 4
        vsetivli        zero, \len, e8, mf4, ta, ma
.elseif \len == 8
        vsetivli        zero, \len, e8, mf2, ta, ma
.elseif \len == 16
        vsetivli        zero, \len, e8, m1, ta, ma
.elseif \len == 32
        li              \an, \len
        vsetvli         zero, \an, e8, m2, ta, ma
.elseif \len == 64
        li              \an, \maxlen
        vsetvli         zero, \an, e8, \mn, ta, ma
.endif
.endm

.macro vsetvlstatic16 len
.ifc \len,4
        vsetvli         zero, zero, e16, mf2, ta, ma
.elseif \len == 8
        vsetvli         zero, zero, e16, m1, ta, ma
.elseif \len == 16
        vsetvli         zero, zero, e16, m2, ta, ma
.else
        vsetvli         zero, zero, e16, m4, ta, ma
.endif
.endm

.macro copy_avg len
func ff_avg\len\()_rvv, zve32x
        csrwi           vxrm, 0
        vsetvlstatic8   \len t0 64
1:
        addi            a4, a4, -1
        vle8.v          v8, (a2)
        vle8.v          v16, (a0)
        vaaddu.vv       v8, v8, v16
        vse8.v          v8, (a0)
        add             a2, a2, a3
        add             a0, a0, a1
        bnez            a4, 1b
        ret
endfunc
.endm

.macro bilin_load dst len op type mn
.ifc \type,v
        add             t5, a2, a3
.elseif \type == h
        addi            t5, a2, 1
.endif
        vle8.v          v8, (a2)
        vle8.v          v0, (t5)
        vwmulu.vx       v16, v0, \mn
        vwmaccsu.vx     v16, t1, v8
        vwadd.wx        v16, v16, t4
        vnsra.wi        v16, v16, 4
        vadd.vv         \dst, v16, v8
.ifc \op,avg
        vle8.v          v16, (a0)
        vaaddu.vv       \dst, \dst, v16
.endif
.endm

.macro bilin_h_v len op type mn
func ff_\op\()_bilin_\len\()\type\()_rvv, zve32x
.ifc \op,avg
        csrwi           vxrm, 0
.endif
        vsetvlstatic8   \len t0 64
        li              t4, 8
        neg             t1, \mn
1:
        addi            a4, a4, -1
        bilin_load      v0, \len, \op, \type, \mn
        vse8.v          v0, (a0)
        add             a2, a2, a3
        add             a0, a0, a1
        bnez            a4, 1b

        ret
endfunc
.endm

const subpel_filters_regular
        .byte  0,  0,   0, 128,   0,   0,  0,  0
        .byte  0,  1,  -5, 126,   8,  -3,  1,  0
        .byte -1,  3, -10, 122,  18,  -6,  2,  0
        .byte -1,  4, -13, 118,  27,  -9,  3, -1
        .byte -1,  4, -16, 112,  37, -11,  4, -1
        .byte -1,  5, -18, 105,  48, -14,  4, -1
        .byte -1,  5, -19,  97,  58, -16,  5, -1
        .byte -1,  6, -19,  88,  68, -18,  5, -1
        .byte -1,  6, -19,  78,  78, -19,  6, -1
        .byte -1,  5, -18,  68,  88, -19,  6, -1
        .byte -1,  5, -16,  58,  97, -19,  5, -1
        .byte -1,  4, -14,  48, 105, -18,  5, -1
        .byte -1,  4, -11,  37, 112, -16,  4, -1
        .byte -1,  3,  -9,  27, 118, -13,  4, -1
        .byte  0,  2,  -6,  18, 122, -10,  3, -1
        .byte  0,  1,  -3,   8, 126,  -5,  1,  0
subpel_filters_sharp:
        .byte  0,  0,   0, 128,   0,   0,  0,  0
        .byte -1,  3,  -7, 127,   8,  -3,  1,  0
        .byte -2,  5, -13, 125,  17,  -6,  3, -1
        .byte -3,  7, -17, 121,  27, -10,  5, -2
        .byte -4,  9, -20, 115,  37, -13,  6, -2
        .byte -4, 10, -23, 108,  48, -16,  8, -3
        .byte -4, 10, -24, 100,  59, -19,  9, -3
        .byte -4, 11, -24,  90,  70, -21, 10, -4
        .byte -4, 11, -23,  80,  80, -23, 11, -4
        .byte -4, 10, -21,  70,  90, -24, 11, -4
        .byte -3,  9, -19,  59, 100, -24, 10, -4
        .byte -3,  8, -16,  48, 108, -23, 10, -4
        .byte -2,  6, -13,  37, 115, -20,  9, -4
        .byte -2,  5, -10,  27, 121, -17,  7, -3
        .byte -1,  3,  -6,  17, 125, -13,  5, -2
        .byte  0,  1,  -3,   8, 127,  -7,  3, -1
subpel_filters_smooth:
        .byte  0,  0,   0, 128,   0,   0,  0,  0
        .byte -3, -1,  32,  64,  38,   1, -3,  0
        .byte -2, -2,  29,  63,  41,   2, -3,  0
        .byte -2, -2,  26,  63,  43,   4, -4,  0
        .byte -2, -3,  24,  62,  46,   5, -4,  0
        .byte -2, -3,  21,  60,  49,   7, -4,  0
        .byte -1, -4,  18,  59,  51,   9, -4,  0
        .byte -1, -4,  16,  57,  53,  12, -4, -1
        .byte -1, -4,  14,  55,  55,  14, -4, -1
        .byte -1, -4,  12,  53,  57,  16, -4, -1
        .byte  0, -4,   9,  51,  59,  18, -4, -1
        .byte  0, -4,   7,  49,  60,  21, -3, -2
        .byte  0, -4,   5,  46,  62,  24, -3, -2
        .byte  0, -4,   4,  43,  63,  26, -2, -2
        .byte  0, -3,   2,  41,  63,  29, -2, -2
        .byte  0, -3,   1,  38,  64,  32, -1, -3
endconst

.macro epel_filter name type regtype
        lla             \regtype\()2, subpel_filters_\name
        li              \regtype\()1, 8
.ifc \type,v
        mul             \regtype\()0, a6, \regtype\()1
.elseif \type == h
        mul             \regtype\()0, a5, \regtype\()1
.endif
        add             \regtype\()0, \regtype\()0, \regtype\()2
        .irp n 1,2,3,4,5,6
        lb              \regtype\n, \n(\regtype\()0)
        .endr
.ifc \regtype,t
        lb              a7, 7(\regtype\()0)
.elseif \regtype == s
        lb              s7, 7(\regtype\()0)
.endif
        lb              \regtype\()0, 0(\regtype\()0)
.endm

.macro epel_load dst len op name type from_mem regtype
        li              a5, 64
.ifc \from_mem, 1
        vle8.v          v22, (a2)
.ifc \type,v
        sub             a2, a2, a3
        vle8.v          v20, (a2)
        sh1add          a2, a3, a2
        vle8.v          v24, (a2)
        add             a2, a2, a3
        vle8.v          v26, (a2)
        add             a2, a2, a3
        vle8.v          v28, (a2)
        add             a2, a2, a3
        vle8.v          v30, (a2)
.elseif \type == h
        addi            a2, a2, -1
        vle8.v          v20, (a2)
        addi            a2, a2, 2
        vle8.v          v24, (a2)
        addi            a2, a2, 1
        vle8.v          v26, (a2)
        addi            a2, a2, 1
        vle8.v          v28, (a2)
        addi            a2, a2, 1
        vle8.v          v30, (a2)
.endif

.ifc \name,smooth
        vwmulu.vx       v16, v24, \regtype\()4
        vwmaccu.vx      v16, \regtype\()2, v20
        vwmaccu.vx      v16, \regtype\()5, v26
        vwmaccsu.vx     v16, \regtype\()6, v28
.else
        vwmulu.vx       v16, v28, \regtype\()6
        vwmaccsu.vx     v16, \regtype\()2, v20
        vwmaccsu.vx     v16, \regtype\()5, v26
.endif

.ifc \regtype,t
        vwmaccsu.vx     v16, a7, v30
.elseif \regtype == s
        vwmaccsu.vx     v16, s7, v30
.endif

.ifc \type,v
        .rept 6
        sub             a2, a2, a3
        .endr
        vle8.v          v28, (a2)
        sub             a2, a2, a3
        vle8.v          v26, (a2)
        sh1add          a2, a3, a2
        add             a2, a2, a3
.elseif \type == h
        addi            a2, a2, -6
        vle8.v          v28, (a2)
        addi            a2, a2, -1
        vle8.v          v26, (a2)
        addi            a2, a2, 3
.endif

.ifc \name,smooth
        vwmaccsu.vx     v16, \regtype\()1, v28
.else
        vwmaccu.vx      v16, \regtype\()1, v28
        vwmulu.vx       v28, v24, \regtype\()4
.endif
        vwmaccsu.vx     v16, \regtype\()0, v26
        vwmulu.vx       v20, v22, \regtype\()3
.else
.ifc \name,smooth
        vwmulu.vx       v16, v8, \regtype\()4
        vwmaccu.vx      v16, \regtype\()2, v4
        vwmaccu.vx      v16, \regtype\()5, v10
        vwmaccsu.vx     v16, \regtype\()6, v12
        vwmaccsu.vx     v16, \regtype\()1, v2
.else
        vwmulu.vx       v16, v2, \regtype\()1
        vwmaccu.vx      v16, \regtype\()6, v12
        vwmaccsu.vx     v16, \regtype\()5, v10
        vwmaccsu.vx     v16, \regtype\()2, v4
        vwmulu.vx       v28, v8, \regtype\()4
.endif
        vwmaccsu.vx     v16, \regtype\()0, v0
        vwmulu.vx       v20, v6, \regtype\()3

.ifc \regtype,t
        vwmaccsu.vx     v16, a7, v14
.elseif \regtype == s
        vwmaccsu.vx     v16, s7, v14
.endif

.endif
        vwadd.wx        v16, v16, a5
        vsetvlstatic16  \len

.ifc \name,smooth
        vwadd.vv        v24, v16, v20
.else
        vwadd.vv        v24, v16, v28
        vwadd.wv        v24, v24, v20
.endif
        vnsra.wi        v24, v24, 7
        vmax.vx         v24, v24, zero
        vsetvlstatic8   \len, zero, 32, m2

        vnclipu.wi      \dst, v24, 0
.ifc \op,avg
        vle8.v          v24, (a0)
        vaaddu.vv       \dst, \dst, v24
.endif

.endm

.macro epel_load_inc dst len op name type from_mem regtype
        epel_load       \dst \len \op \name \type \from_mem \regtype
        add             a2, a2, a3
.endm

.macro epel len op name type vlen
func ff_\op\()_8tap_\name\()_\len\()\type\()_rvv\vlen\(), zve32x
        epel_filter     \name \type t
.if \vlen < 256
        vsetvlstatic8   \len a5 32 m2
.else
        vsetvlstatic8   \len a5 64 m2
.endif
.ifc \op,avg
        csrwi           vxrm, 0
.endif

1:
        addi            a4, a4, -1
        epel_load       v30 \len \op \name \type 1 t
        vse8.v          v30, (a0)
.if \len == 64 && \vlen < 256
        addi            a0, a0, 32
        addi            a2, a2, 32
        epel_load       v30 \len \op \name \type 1 t
        vse8.v          v30, (a0)
        addi            a0, a0, -32
        addi            a2, a2, -32
.endif
        add             a2, a2, a3
        add             a0, a0, a1
        bnez            a4, 1b

        ret
endfunc
.endm

.irp len 64, 32, 16, 8, 4
        copy_avg \len
        .irp op put avg
                bilin_h_v \len \op h a5
                bilin_h_v \len \op v a6
                .irp name regular sharp smooth
                        .irp type h v
                                epel \len \op \name \type 128
                                epel \len \op \name \type 256
                        .endr
                .endr
        .endr
.endr
