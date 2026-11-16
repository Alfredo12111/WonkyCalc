# Data-only protocol: operation, argument count, then (rank, dimensions,
# element count, one decimal per line) for each argument. No •BQN evaluation.
lines ← •FLines "array-input.txt"
p ← 0
Next ← {𝕩 ⋄ r←p⊑lines ⋄ p↩p+1 ⋄ r}
Num ← {𝕩 ⋄ •ParseFloat Next 0}
Read ← {
  𝕩
  rank←Num 0
  shape←Num¨ ↕rank
  count←Num 0
  vals←Num¨ ↕count
  {rank=0 ? ⊑vals ; shape⥊vals}
}
op ← Next 0
args ← Read¨ ↕Num 0
a ← ⊑args
b ← ⊑⌽args
Det ← {
  mat←𝕩
  n←⊑≢𝕩
  row←0⊏mat
  {n=1 ? ⊑⥊mat ; +´{i←𝕩 ⋄ ((¯1⋆i)×i⊑row)×Det ((↕n)≠i)/⎉1 (1↓mat)}¨↕n}
}
Run ← {
  𝕩
  op≡"array" ? >args ;
  op≡"add" ? a+b ; op≡"sub" ? a-b ;
  op≡"mul" ? a×b ; op≡"div" ? a÷b ;
  op≡"neg" ? -a ; op≡"abs" ? |a ;
  op≡"percent" ? a÷100 ;
  (op≡"unit_m")∨(op≡"unit_kg")∨(op≡"unit_s")∨(op≡"unit_seconds") ? a ;
  op≡"unit_cm" ? a÷100 ; op≡"unit_km" ? a×1000 ;
  (op≡"unit_ms")∨(op≡"unit_g") ? a÷1000 ;
  op≡"transpose" ? ⍉a ;
  op≡"dot" ? +´a×b ;
  op≡"matmul" ? {row←𝕩 ⋄ {+´row×𝕩}˘⍉b}˘a ;
  op≡"det" ? Det a ;
  op≡"norm" ? √+´×˜⥊a ;
  op≡"sum" ? +´⥊a ;
  op≡"mean" ? (+´⥊a)÷≠⥊a ;
  op≡"min" ? ⌊´⥊a ; op≡"max" ? ⌈´⥊a ;
  op≡"audit" ? a ;
  ! "This operation is not available for arrays."
}
started ← •MonoTime @
result ← Run 0
!∧´(∞>|⥊result)
elapsed ← 1000×(•MonoTime @)-started
# •Repr emits exact round-trippable decimal strings; the host only transports them.
out ← (⟨•Repr ≠≢result⟩)∾(•Repr¨≢result)∾(⟨•Repr ≠⥊result⟩)∾•Repr¨⥊result
"array-result.txt" •FLines out
"bqn-ms.txt" •FChars •Repr elapsed
