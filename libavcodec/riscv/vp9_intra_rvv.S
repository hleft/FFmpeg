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

.macro avgdc size
        vwredsumu.vs v16, v8, v16
        vsetivli     zero, 1, e16, m1, ta, ma
        vmv.x.s      t1, v16
        addi         t1, t1, 1 << (\size - 1)
        srai         t1, t1, \size
.endm

.macro getdc type size
.ifc \type,top
        vmv.v.x      v16, zero
        vle8.v       v8, (a3)
        avgdc        \size
.else
.ifc \type,left
        vmv.v.x      v16, zero
        vle8.v       v8, (a2)
        avgdc        \size
.else
.ifc \type,dc
        vmv.v.x      v16, zero
        vle8.v       v8, (a2)
        vwredsumu.vs v16, v8, v16
        vle8.v       v8, (a3)
        avgdc        \size
.else
        li           t1, \type
.endif
.endif
.endif
.endm

.macro dc_e32 type size n restore
.ifc \size,32
        li           t0, 32
        vsetvli      zero, t0, e8, m2, ta, ma
.else
        vsetivli     zero, 16, e8, m1, ta, ma
.endif
        getdc        \type \n

.if \restore == 1 && \size == 32
        vsetvli      zero, t0, e8, m2, ta, ma
.elseif \restore == 1 && \size == 16
        vsetivli     zero, 16, e8, m1, ta, ma
.endif
        vmv.v.x      v0, t1

        .rept \size
        vse8.v       v0, (a0)
        add          a0, a0, a1
        .endr

        ret
.endm

.macro dc_e64 type size n restore
        vsetivli     zero, 8, e8, mf2, ta, ma
        getdc        \type \n

        li           t0, 64
        vsetvli      zero, t0, e8, m4, ta, ma
        vmv.v.x      v0, t1
        vsetivli     zero, 8, e8, mf2, ta, ma
        vsse64.v     v0, (a0), a1

        ret
.endm

.macro func_dc name size type n restore ext
func ff_\()\name\()_\()\size\()x\size\()_rvv, \ext
.if \size == 8
        dc_e64 \type \size \n \restore
.else
        dc_e32 \type \size \n \restore
.endif
endfunc
.endm

func_dc dc_127   32  127  0  0  zve32x
func_dc dc_127   16  127  0  0  zve32x
func_dc dc_127   8   127  0  0  zve64x
func_dc dc_128   32  128  0  0  zve32x
func_dc dc_128   16  128  0  0  zve32x
func_dc dc_128   8   128  0  0  zve64x
func_dc dc_129   32  129  0  0  zve32x
func_dc dc_129   16  129  0  0  zve32x
func_dc dc_129   8   129  0  0  zve64x
func_dc dc       32  dc   6  1  zve32x
func_dc dc       16  dc   5  1  zve32x
func_dc dc       8   dc   4  0  zve64x
func_dc dc_left  32  left 5  1  zve32x
func_dc dc_left  16  left 4  1  zve32x
func_dc dc_left  8   left 3  0  zve64x
func_dc dc_top   32  top  5  1  zve32x
func_dc dc_top   16  top  4  1  zve32x
func_dc dc_top   8   top  3  0  zve64x

func ff_h_32x32_rvv, zve32x
        li           t0, 32
        addi         a2, a2, 31
        vsetvli      zero, t0, e8, m2, ta, ma

        .rept 2
        .irp n 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
        lbu          t1, (a2)
        addi         a2, a2, -1
        vmv.v.x      v\n, t1
        .endr
        .irp n 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        .endr

        ret
endfunc

func ff_h_16x16_rvv, zve32x
        addi         a2, a2, 15
        vsetivli     zero, 16, e8, m1, ta, ma

        .irp n 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23
        lbu          t1, (a2)
        addi         a2, a2, -1
        vmv.v.x      v\n, t1
        .endr
        .irp n 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        vse8.v       v23, (a0)

        ret
endfunc

func ff_h_8x8_rvv, zve32x
        addi         a2, a2, 7
        vsetivli     zero, 8, e8, mf2, ta, ma

        .irp n 8, 9, 10, 11, 12, 13, 14, 15
        lbu          t1, (a2)
        addi         a2, a2, -1
        vmv.v.x      v\n, t1
        .endr
        .irp n 8, 9, 10, 11, 12, 13, 14
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        vse8.v       v15, (a0)

        ret
endfunc

.macro tm_sum dst, top, offset
        lbu          t3, \offset(a2)
        sub          t3, t3, a4
        vadd.vx      \dst, \top, t3
.endm

func ff_tm_32x32_rvv, zve32x
        lbu          a4, -1(a3)
        li           t5, 32

        .macro tm_sum32 n1,n2,n3,n4,n5,n6,n7,n8
        vsetvli      zero, t5, e16, m4, ta, ma
        vle8.v       v8, (a3)
        vzext.vf2    v28, v8

        tm_sum       v0, v28, \n1
        tm_sum       v4, v28, \n2
        tm_sum       v8, v28, \n3
        tm_sum       v12, v28, \n4
        tm_sum       v16, v28, \n5
        tm_sum       v20, v28, \n6
        tm_sum       v24, v28, \n7
        tm_sum       v28, v28, \n8

        .irp n 0, 4, 8, 12, 16, 20, 24, 28
        vmax.vx      v\n, v\n, zero
        .endr

        vsetvli      zero, zero, e8, m2, ta, ma
        .irp n 0, 4, 8, 12, 16, 20, 24, 28
        vnclipu.wi   v\n, v\n, 0
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        .endm

        tm_sum32     31, 30, 29, 28, 27, 26, 25, 24
        tm_sum32     23, 22, 21, 20, 19, 18, 17, 16
        tm_sum32     15, 14, 13, 12, 11, 10, 9, 8
        tm_sum32     7, 6, 5, 4, 3, 2, 1, 0

        ret
endfunc

func ff_tm_16x16_rvv, zve32x
        vsetivli      zero, 16, e16, m2, ta, ma
        vle8.v        v8, (a3)
        vzext.vf2     v30, v8
        lbu           a4, -1(a3)

        tm_sum       v0, v30, 15
        tm_sum       v2, v30, 14
        tm_sum       v4, v30, 13
        tm_sum       v6, v30, 12
        tm_sum       v8, v30, 11
        tm_sum       v10, v30, 10
        tm_sum       v12, v30, 9
        tm_sum       v14, v30, 8
        tm_sum       v16, v30, 7
        tm_sum       v18, v30, 6
        tm_sum       v20, v30, 5
        tm_sum       v22, v30, 4
        tm_sum       v24, v30, 3
        tm_sum       v26, v30, 2
        tm_sum       v28, v30, 1
        tm_sum       v30, v30, 0

        .irp n 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
        vmax.vx      v\n, v\n, zero
        .endr

        vsetvli      zero, zero, e8, m1, ta, ma
        .irp n 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28
        vnclipu.wi   v\n, v\n, 0
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        vnclipu.wi   v30, v30, 0
        vse8.v       v30, (a0)

        ret
endfunc

func ff_tm_8x8_rvv, zve32x
        vsetivli     zero, 8, e16, m1, ta, ma
        vle8.v       v8, (a3)
        vzext.vf2    v28, v8
        lbu          a4, -1(a3)

        tm_sum       v16, v28, 7
        tm_sum       v17, v28, 6
        tm_sum       v18, v28, 5
        tm_sum       v19, v28, 4
        tm_sum       v20, v28, 3
        tm_sum       v21, v28, 2
        tm_sum       v22, v28, 1
        tm_sum       v23, v28, 0

        .irp n 16, 17, 18, 19, 20, 21, 22, 23
        vmax.vx      v\n, v\n, zero
        .endr

        vsetvli      zero, zero, e8, mf2, ta, ma
        .irp n 16, 17, 18, 19, 20, 21, 22
        vnclipu.wi   v\n, v\n, 0
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        vnclipu.wi   v24, v23, 0
        vse8.v       v24, (a0)

        ret
endfunc

func ff_tm_4x4_rvv, zve32x
        vsetivli     zero, 4, e16, mf2, ta, ma
        vle8.v       v8, (a3)
        vzext.vf2    v28, v8
        lbu          a4, -1(a3)

        tm_sum       v16, v28, 3
        tm_sum       v17, v28, 2
        tm_sum       v18, v28, 1
        tm_sum       v19, v28, 0

        .irp n 16, 17, 18, 19
        vmax.vx      v\n, v\n, zero
        .endr

        vsetvli      zero, zero, e8, mf4, ta, ma
        .irp n 16, 17, 18
        vnclipu.wi   v\n, v\n, 0
        vse8.v       v\n, (a0)
        add          a0, a0, a1
        .endr
        vnclipu.wi   v24, v19, 0
        vse8.v       v24, (a0)

        ret
endfunc
