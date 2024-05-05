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

.macro vsetvlstatic8 len
.if \len <= 4
        vsetivli        zero, \len, e8, mf4, ta, ma
.elseif \len <= 8
        vsetivli        zero, \len, e8, mf2, ta, ma
.elseif \len <= 16
        vsetivli        zero, \len, e8, m1, ta, ma
.elseif \len <= 31
        vsetivli        zero, \len, e8, m2, ta, ma
.endif
.endm

.macro vsetvlstatic16 len
.if \len <= 4
        vsetivli        zero, \len, e16, mf2, ta, ma
.elseif \len <= 8
        vsetivli        zero, \len, e16, m1, ta, ma
.elseif \len <= 16
        vsetivli        zero, \len, e16, m2, ta, ma
.endif
.endm

.macro vp8_idct_dc_add
        vlse32.v      v0, (a0), a2
        lh            a5, 0(a1)
        sh            zero, 0(a1)
        addi          a5, a5, 4
        srai          t1, a5, 3
        vsetivli      zero, 4*4, e16, m2, ta, ma
        vzext.vf2     v2, v0
        vadd.vx       v2, v2, t1
        vmax.vx       v2, v2, zero
        vsetvli       zero, zero, e8, m1, ta, ma
        vnclipu.wi    v0, v2, 0
        vsetivli      zero, 4, e8, mf4, ta, ma
        vsse32.v      v0, (a0), a2
.endm

.macro vp8_idct_dc_addy
        vp8_idct_dc_add
        addi          a0, a0, 4
        addi          a1, a1, 32
.endm

func ff_vp8_idct_dc_add_rvv, zve32x
        vsetivli      zero, 4, e8, mf4, ta, ma
        vp8_idct_dc_add

        ret
endfunc

func ff_vp8_idct_dc_add4y_rvv, zve32x
        vsetivli      zero, 4, e8, mf4, ta, ma
        .rept 3
        vp8_idct_dc_addy
        .endr
        vp8_idct_dc_add

        ret
endfunc

func ff_vp8_idct_dc_add4uv_rvv, zve32x
        vsetivli      zero, 4, e8, mf4, ta, ma
        vp8_idct_dc_addy
        vp8_idct_dc_add
        addi          a0, a0, -4
        sh2add        a0, a2, a0
        addi          a1, a1, 32
        vp8_idct_dc_addy
        vp8_idct_dc_add

        ret
endfunc

.macro filter_abs dst diff fI
        vneg.v          v8, \diff
        vmax.vv         \dst, v8, \diff
        vmsleu.vx       v8, \dst, \fI
        vmand.mm        v27, v27, v8
.endm

.macro filter_fmin len a f1 p0f2 q0f1
        vsetvlstatic16  \len
        vsext.vf2       \q0f1, \a
        vmin.vx         \p0f2, \q0f1, a7
        vmin.vx         \q0f1, \q0f1, t3
        vadd.vi         \p0f2, \p0f2, 3
        vadd.vi         \q0f1, \q0f1, 4
        vsra.vi         \p0f2, \p0f2, 3
        vsra.vi         \f1,   \q0f1, 3
        vadd.vv         \p0f2, \p0f2, v8
        vsub.vv         \q0f1, v16, \f1
        vmax.vx         \p0f2, \p0f2, zero
        vmax.vx         \q0f1, \q0f1, zero
.endm

.macro filter len type normal inner dst stride fE fI thresh
.ifc \type,v
        slli            a6, \stride, 1
        sub             t2, \dst, a6
        add             t4, \dst, \stride
        sub             t1, \dst, \stride
        vle8.v          v1, (t2)
        vle8.v          v11, (t4)
        vle8.v          v17, (t1)
        vle8.v          v22, (\dst)
        .if \normal
        sub             t3, t2, a6
        sub             t0, t1, a6
        add             t6, \dst, a6
        add             a7, t4, a6
        vle8.v          v2, (t3)
        vle8.v          v15, (t0)
        vle8.v          v10, (t6)
        vle8.v          v14, (a7)
        .endif
.else
        addi            t1, \dst, -1
        addi            a6, \dst, -2
        addi            t4, \dst, 1
        vlse8.v         v1, (a6), \stride
        vlse8.v         v11, (t4), \stride
        vlse8.v         v17, (t1), \stride
        vlse8.v         v22, (\dst), \stride
        .if \normal
        addi            t5, \dst, -4
        addi            t0, \dst, -3
        addi            t6, \dst, 2
        addi            a7, \dst, 3
        vlse8.v         v2, (t5), \stride
        vlse8.v         v15, (t0), \stride
        vlse8.v         v10, (t6), \stride
        vlse8.v         v14, (a7), \stride
        .endif
.endif
        vwsubu.vv       v12, v1, v11             // p1-q1
        vwsubu.vv       v24, v22, v17            // q0-p0
.if \normal
        vwsubu.vv       v30, v1, v17
        vwsubu.vv       v20, v11, v22
        vwsubu.vv       v28, v1, v15
        vwsubu.vv       v4, v2, v15
        vwsubu.vv       v6, v10, v11
        vwsubu.vv       v2, v14, v10
.endif
        vnclip.wi       v23, v12, 0
        vsetvlstatic16  \len
        // vp8_simple_limit(dst + i, stride, flim)
        li              a7, 2
        vneg.v          v18, v12
        vmax.vv         v18, v18, v12
        vneg.v          v8, v24
        vmax.vv         v8, v8, v24
        vsrl.vi         v18, v18, 1
        vmacc.vx        v18, a7, v8
        vmsleu.vx       v0, v18, \fE
.if \normal
        vneg.v          v18, v30
        vmax.vv         v30, v18, v30
        vmsleu.vx       v27, v30, \fI
        filter_abs      v18 v28 \fI
        filter_abs      v18 v4 \fI
        filter_abs      v18 v6 \fI
        filter_abs      v18 v2 \fI
        filter_abs      v20 v20 \fI
        vmand.mm        v27, v0, v27             // vp8_simple_limit && normal

        vmsgtu.vx       v20, v20, \thresh        // hev
        vmsgtu.vx       v3, v30, \thresh
        vmor.mm         v3, v3, v20              // v3 = hev: > thresh
        vzext.vf2       v18, v1                  // v18 = p1
        vmand.mm        v0, v27, v3              // v0 = normal && hev
        vzext.vf2       v20, v11                 // v12 = q1
        vmnot.m         v3, v3                   // v3 = !hv
.endif

        li              t5, 3
        li              a7, 124
        li              t3, 123
        vsext.vf2       v4, v23
        vzext.vf2       v8, v17                  // p0
        vzext.vf2       v16, v22                 // q0
        vmul.vx         v30, v24, t5
        vadd.vv         v12, v30, v4
        vsetvlstatic8   \len
        vnclip.wi       v11, v12, 0
        filter_fmin     \len v11 v24 v4 v6
        vsetvlstatic8   \len
        vnclipu.wi      v4, v4, 0
        vnclipu.wi      v6, v6, 0

.ifc \type,v
        vse8.v          v4, (t1), v0.t
        vse8.v          v6, (\dst), v0.t
.else
        vsse8.v         v4, (t1), \stride, v0.t
        vsse8.v         v6, (\dst), \stride, v0.t
.endif

.if \normal
        vmand.mm        v0, v27, v3              // vp8_normal_limit & !hv

        .if \inner
        vnclip.wi       v30, v30, 0
        filter_fmin     \len v30 v24 v4 v6
        vadd.vi         v24, v24, 1
        vsra.vi         v24, v24, 1              // (f1 + 1) >> 1;
        vadd.vv         v8, v18, v24
        vsub.vv         v10, v20, v24
        .else
        li              t5, 27
        li              t3, 9
        li              a7, 18
        vwmul.vx        v2, v11, t5
        vwmul.vx        v6, v11, t3
        vwmul.vx        v4, v11, a7
        vsetvlstatic16  \len
        li              a7, 63
        vzext.vf2       v14, v15                 // p2
        vzext.vf2       v24, v10                 // q2
        vadd.vx         v2, v2, a7
        vadd.vx         v4, v4, a7
        vadd.vx         v6, v6, a7
        vsra.vi         v2, v2, 7                // a0
        vsra.vi         v12, v4, 7               // a1
        vsra.vi         v6, v6, 7                // a2
        vadd.vv         v14, v14, v6             // p2 + a2
        vsub.vv         v22, v24, v6             // q2 - a2
        vsub.vv         v10, v20, v12            // q1 - a1
        vadd.vv         v4, v8, v2               // p0 + a0
        vsub.vv         v6, v16, v2              // q0 - a0
        vadd.vv         v8, v12, v18             // a1 + p1
        vmax.vx         v4, v4, zero
        vmax.vx         v6, v6, zero
        vmax.vx         v14, v14, zero
        vmax.vx         v16, v22, zero
        .endif

        vmax.vx         v8, v8, zero
        vmax.vx         v10, v10, zero
        vsetvlstatic8   \len
        vnclipu.wi      v4, v4, 0
        vnclipu.wi      v5, v6, 0
        vnclipu.wi      v6, v8, 0
        vnclipu.wi      v7, v10, 0
        .ifc \type,v
        vse8.v          v4, (t1), v0.t
        vse8.v          v5, (\dst), v0.t
        vse8.v          v6, (t2), v0.t
        vse8.v          v7, (t4), v0.t
        .else
        vsse8.v         v4, (t1), \stride, v0.t
        vsse8.v         v5, (\dst), \stride, v0.t
        vsse8.v         v6, (a6), \stride, v0.t
        vsse8.v         v7, (t4), \stride, v0.t
        .endif
        .if !\inner
        vnclipu.wi      v14, v14, 0
        vnclipu.wi      v16, v16, 0
        .ifc \type,v
        vse8.v          v14, (t0), v0.t
        vse8.v          v16, (t6), v0.t
        .else
        vsse8.v         v14, (t0), \stride, v0.t
        vsse8.v         v16, (t6), \stride, v0.t
        .endif
        .endif
.endif
.endm

func ff_vp8_v_loop_filter16_simple_rvv, zve32x
        vsetvlstatic8   16
        filter 16 v 0 0 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_h_loop_filter16_simple_rvv, zve32x
        vsetvlstatic8   16
        filter 16 h 0 0 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_h_loop_filter16_inner_rvv, zve32x
        vsetvlstatic8   16
        filter 16 h 1 1 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_v_loop_filter16_inner_rvv, zve32x
        vsetvlstatic8   16
        filter 16 v 1 1 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_v_loop_filter8uv_inner_rvv, zve32x
        vsetvlstatic8   8
        filter 8 v 1 1 a0 a2 a3 a4 a5
        filter 8 v 1 1 a1 a2 a3 a4 a5
        ret
endfunc

func ff_vp8_v_loop_filter16_rvv, zve32x
        vsetvlstatic8   16
        filter 16 v 1 0 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_h_loop_filter16_rvv, zve32x
        vsetvlstatic8   16
        filter 16 h 1 0 a0 a1 a2 a3 a4
        ret
endfunc

func ff_vp8_v_loop_filter8uv_rvv, zve32x
        vsetvlstatic8   8
        filter 8 v 1 0 a0 a2 a3 a4 a5
        filter 8 v 1 0 a1 a2 a3 a4 a5
        ret
endfunc

.macro bilin_load dst len type mn
.ifc \type,v
        add             t5, a2, a3
.else
        addi            t5, a2, 1
.endif
        vle8.v          \dst, (a2)
        vle8.v          v2, (t5)
        vwmulu.vx       v28, \dst, t1
        vwmaccu.vx      v28, \mn, v2
        vwaddu.wx       v24, v28, t4
        vnsra.wi        \dst, v24, 3
.endm

.macro put_vp8_bilin_h_v len type mn
func ff_put_vp8_bilin\len\()_\type\()_rvv, zve32x
        vsetvlstatic8   \len
        li              t1, 8
        li              t4, 4
        sub             t1, t1, \mn
1:
        addi            a4, a4, -1
        bilin_load      v0, \len, \type, \mn
        vse8.v          v0, (a0)
        add             a2, a2, a3
        add             a0, a0, a1
        bnez            a4, 1b

        ret
endfunc
.endm

.macro put_vp8_bilin_hv len
func ff_put_vp8_bilin\len\()_hv_rvv, zve32x
        vsetvlstatic8   \len
        li              t3, 8
        sub             t1, t3, a5
        sub             t2, t3, a6
        li              t4, 4
        bilin_load      v4, \len, h, a5
        add             a2, a2, a3
1:
        addi            a4, a4, -1
        vwmulu.vx       v20, v4, t2
        bilin_load      v4, \len, h, a5
        vwmaccu.vx      v20, a6, v4
        vwaddu.wx       v24, v20, t4
        vnsra.wi        v0, v24, 3
        vse8.v          v0, (a0)
        add             a2, a2, a3
        add             a0, a0, a1
        bnez            a4, 1b

        ret
endfunc
.endm

const subpel_filters
        .byte 0,  -6, 123,  12,  -1, 0
        .byte 2, -11, 108,  36,  -8, 1
        .byte 0,  -9,  93,  50,  -6, 0
        .byte 3, -16,  77,  77, -16, 3
        .byte 0,  -6,  50,  93,  -9, 0
        .byte 1,  -8,  36, 108, -11, 2
        .byte 0,  -1,  12, 123,  -6, 0
endconst

.macro epel_filter size type regtype
        lla             \regtype\()2, subpel_filters
.ifc \type,v
        addi            \regtype\()0, a6, -1
.else
        addi            \regtype\()0, a5, -1
.endif
        li              \regtype\()1, 6
        mul             \regtype\()0, \regtype\()0, \regtype\()1
        add             \regtype\()0, \regtype\()0, \regtype\()2
        .irp n 1,2,3,4
        lb              \regtype\n, \n(\regtype\()0)
        .endr
.ifc \size,6
        lb              \regtype\()5, 5(\regtype\()0)
        lb              \regtype\()0, (\regtype\()0)
.endif
.endm

.macro epel_load dst len size type from_mem regtype
.ifc \type,v
        mv              a5, a3
.else
        li              a5, 1
.endif
        sub             t6, a2, a5
        add             a7, a2, a5

.if \from_mem
        vle8.v          v24, (a2)
        vle8.v          v22, (t6)
        vle8.v          v26, (a7)
        add             a7, a7, a5
        vle8.v          v28, (a7)
        vwmulu.vx       v16, v24, \regtype\()2
        vwmulu.vx       v20, v26, \regtype\()3
.ifc \size,6
        sub             t6, t6, a5
        add             a7, a7, a5
        vle8.v          v24, (t6)
        vle8.v          v26, (a7)
        vwmaccu.vx      v16, \regtype\()0, v24
        vwmaccu.vx      v16, \regtype\()5, v26
.endif
        vwmaccsu.vx     v16, \regtype\()1, v22
        vwmaccsu.vx     v16, \regtype\()4, v28
.else
        vwmulu.vx       v16, v4, \regtype\()2
        vwmulu.vx       v20, v6, \regtype\()3
        .ifc \size,6
        vwmaccu.vx      v16, \regtype\()0, v0
        vwmaccu.vx      v16, \regtype\()5, v10
        .endif
        vwmaccsu.vx     v16, \regtype\()1, v2
        vwmaccsu.vx     v16, \regtype\()4, v8
.endif
        li              t6, 64
        vwadd.wx        v16, v16, t6
        vsetvlstatic16  \len
        vwadd.vv        v24, v16, v20
        vnsra.wi        v24, v24, 7
        vmax.vx         v24, v24, zero
        vsetvlstatic8   \len
        vnclipu.wi      \dst, v24, 0
.endm

.macro epel_load_inc dst len size type from_mem regtype
        epel_load       \dst \len \size \type \from_mem \regtype
        add             a2, a2, a3
.endm

.macro epel len size type
func ff_put_vp8_epel\len\()_\type\()\size\()_rvv, zve32x
        epel_filter     \size \type t
        vsetvlstatic8   \len
1:
        addi            a4, a4, -1
        epel_load_inc   v30 \len \size \type 1 t
        vse8.v          v30, (a0)
        add             a0, a0, a1
        bnez            a4, 1b

        ret
endfunc
.endm

#if __riscv_xlen == 64
.macro epel_hv len hsize vsize
func ff_put_vp8_epel\len\()_h\hsize\()v\vsize\()_rvv, zve32x
        addi            sp, sp, -48
        .irp n 0,1,2,3,4,5
        sd              s\n, \n\()<<3(sp)
        .endr
        sub             a2, a2, a3
        epel_filter     \hsize h t
        epel_filter     \vsize v s
        vsetvlstatic8   \len
.if \hsize == 6 || \vsize == 6
        sub             a2, a2, a3
        epel_load_inc   v0 \len \hsize h 1 t
.endif
        epel_load_inc   v2 \len \hsize h 1 t
        epel_load_inc   v4 \len \hsize h 1 t
        epel_load_inc   v6 \len \hsize h 1 t
        epel_load_inc   v8 \len \hsize h 1 t
.if \hsize == 6 || \vsize == 6
        epel_load_inc   v10 \len \hsize h 1 t
.endif
        addi            a4, a4, -1
1:
        addi            a4, a4, -1
        epel_load       v30 \len \vsize v 0 s
        vse8.v          v30, (a0)
.if \hsize == 6 || \vsize == 6
        vmv.v.v         v0, v2
.endif
        vmv.v.v         v2, v4
        vmv.v.v         v4, v6
        vmv.v.v         v6, v8
.if \hsize == 6 || \vsize == 6
        vmv.v.v         v8, v10
        epel_load_inc   v10 \len \hsize h 1 t
.else
        epel_load_inc   v8 \len 4 h 1 t
.endif
        add             a0, a0, a1
        bnez            a4, 1b
        epel_load       v30 \len \vsize v 0 s
        vse8.v          v30, (a0)

        .irp n 0,1,2,3,4,5
        ld              s\n, \n\()<<3(sp)
        .endr
        addi            sp, sp, 48

        ret
endfunc
.endm
#endif

.irp len 16,8,4
put_vp8_bilin_h_v \len h a5
put_vp8_bilin_h_v \len v a6
put_vp8_bilin_hv \len
epel \len 6 h
epel \len 4 h
epel \len 6 v
epel \len 4 v
#if __riscv_xlen == 64
epel_hv \len 6 6
epel_hv \len 4 4
epel_hv \len 6 4
epel_hv \len 4 6
#endif
.endr
