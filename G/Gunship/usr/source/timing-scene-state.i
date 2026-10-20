; Build the native 27-word scene endpoint without the +04288 interpolation
; loop or its previous-frame buffers. Standalone, not installed.
; a0=committed 12-byte camera, a1=committed 36-byte six-object coordinates,
; a2=native hunk 6 (special object's split coordinate bytes),
; a3=private 54-byte destination corresponding to render context +0e.
; All inputs must be stable and destination must not overlap them.
; Returns d0=0; all other registers preserved. Only destination/stack writes.
; World callers must supply committed poses, never renderer predictions.
; This only constructs the endpoint; cell selection/transforms are separate.
SCENE_STATE_SIZE equ 54
scene_state_build:
 movem.l d1/a0-a3,-(sp)
 moveq #5,d1
.camera:
 move.w (a0)+,(a3)+
 dbf d1,.camera
 moveq #17,d1
.objects:
 move.w (a1)+,(a3)+
 dbf d1,.objects
 move.b $3be3(a2),(a3)+
 move.b $3c5d(a2),(a3)+
 move.b $3c63(a2),(a3)+
 move.b $3cdd(a2),(a3)+
 move.b $3ddd(a2),(a3)+
 move.b $3d5d(a2),(a3)+
 moveq #0,d0
 movem.l (sp)+,d1/a0-a3
 rts
