import CfProofs.Greedy.Huffman.Base

open HuffTree

/-!
# splitLeaf–huffman Commutation Lemma

Blanchette (2009) "Proof Pearl", translated to Lean 4.

`splitLeaf (huffman ts) s1 s1 s2 f1 f2 = huffman (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2))`

**Key condition**: `rootFreq (splitLeaf t) = rootFreq t` for all trees `t` in the forest.
This is preserved by `unite` (rootFreq adds) and `insortTree` (comparisons use rootFreq).
No consistency or disjointness required.
-/

lemma insortTree_length (t : HuffTree) (ts : List HuffTree) : (insortTree t ts).length = ts.length + 1 := by
  induction ts with
  | nil => simp [insortTree]
  | cons u us ih => simp [insortTree]; split <;> simp [ih]

@[simp] lemma splitLeaf_unite (l r : HuffTree) (z a b fa fb : ℕ) :
    splitLeaf (unite l r) z a b fa fb = unite (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb) := by
  simp [unite, splitLeaf]

/-- `rootFreq` of `unite` is the sum. -/
@[simp] lemma rootFreq_unite (t1 t2 : HuffTree) : rootFreq (unite t1 t2) = rootFreq t1 + rootFreq t2 := by
  simp [unite, rootFreq]

/-! ### RootFreq preservation is the ONLY condition needed -/

lemma rootFreq_splitLeaf_unite (t1 t2 : HuffTree) (s1 s2 f1 f2 : ℕ)
    (h1 : rootFreq (splitLeaf t1 s1 s1 s2 f1 f2) = rootFreq t1)
    (h2 : rootFreq (splitLeaf t2 s1 s1 s2 f1 f2) = rootFreq t2) :
    rootFreq (splitLeaf (unite t1 t2) s1 s1 s2 f1 f2) = rootFreq (unite t1 t2) := by
  simp [h1, h2]

/-! ### `insortTree` commutation with `map splitLeaf` -/

lemma map_splitLeaf_insortTree (U : HuffTree) (ts : List HuffTree) (s1 s2 f1 f2 : ℕ)
    (hU_rf : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U)
    (hts_rf : ∀ t ∈ ts, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t) :
    (insortTree U ts).map (λ t => splitLeaf t s1 s1 s2 f1 f2)
    = insortTree (splitLeaf U s1 s1 s2 f1 f2) (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2)) := by
  induction ts generalizing U with
  | nil => simp [insortTree]
  | cons t us ih =>
    have h_us_rf : ∀ u ∈ us, rootFreq (splitLeaf u s1 s1 s2 f1 f2) = rootFreq u :=
      fun u hu => hts_rf u (by simp [hu])
    have ht_rf := hts_rf t (by simp)
    simp [insortTree, List.map_cons]
    by_cases h_rf : rootFreq U ≤ rootFreq t
    · have h_rf' : rootFreq (splitLeaf U s1 s1 s2 f1 f2) ≤ rootFreq (splitLeaf t s1 s1 s2 f1 f2) := by
        rw [hU_rf, ht_rf]; exact h_rf
      simp [h_rf, h_rf']
    · have h_rf' : ¬ rootFreq (splitLeaf U s1 s1 s2 f1 f2) ≤ rootFreq (splitLeaf t s1 s1 s2 f1 f2) := by
        rw [hU_rf, ht_rf]; exact h_rf
      simp [h_rf, h_rf', ih U hU_rf h_us_rf]

/-! ### `insortTree` membership -/

lemma mem_insortTree (t : HuffTree) (ts : List HuffTree) (u : HuffTree) :
    u ∈ insortTree t ts ↔ u = t ∨ u ∈ ts := by
  induction ts generalizing t with
  | nil => simp [insortTree]
  | cons v vs ih =>
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq v
    · simp [h, ih, or_assoc]
    · simp [h, ih, or_assoc, or_comm, or_left_comm]

lemma forall_mem_insortTree {P : HuffTree → Prop} {U : HuffTree} {ts : List HuffTree}
    (hU : P U) (hts : ∀ t ∈ ts, P t) : ∀ t ∈ insortTree U ts, P t := by
  intro t ht
  rcases (mem_insortTree U ts t).mp ht with (rfl | ht')
  · exact hU
  · exact hts t ht'

/-! ### MAIN THEOREM -/

theorem splitLeaf_huffman_commute_general (ts : List HuffTree) (s1 s2 f1 f2 : ℕ)
    (h_nonempty : ts ≠ [])
    (h_rf_forest : ∀ t ∈ ts, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t) :
    splitLeaf (huffman ts) s1 s1 s2 f1 f2
    = huffman (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2)) := by
  induction ts using huffman.induct with
  | case1 =>
    exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman]
  | case3 t1 t2 rest IH =>
    have h1_rf := h_rf_forest t1 (by simp)
    have h2_rf := h_rf_forest t2 (by simp)
    have h_rest_rf : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      fun t ht => h_rf_forest t (by simp [ht])
    let U := unite t1 t2
    -- rootFreq preserved for U
    have hU_rf : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U :=
      rootFreq_splitLeaf_unite t1 t2 s1 s2 f1 f2 h1_rf h2_rf
    -- rootFreq preserved for the recursive forest (U + rest, via insortTree)
    have h_rec_rf : ∀ t ∈ insortTree U rest,
        rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      forall_mem_insortTree (P := λ t => rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t)
        hU_rf h_rest_rf
    simp [huffman, List.map_cons, splitLeaf_unite, U]
    have h_nonempty_rec : insortTree U rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length U rest]
      omega
    rw [IH h_nonempty_rec h_rec_rf]
    have hU_rf' : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U :=
      h_rec_rf U ((mem_insortTree U rest U).mpr (Or.inl rfl))
    have h_rest_rf' : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      fun t ht => h_rec_rf t ((mem_insortTree U rest t).mpr (Or.inr ht))
    rw [map_splitLeaf_insortTree U rest s1 s2 f1 f2 hU_rf' h_rest_rf']
    rfl

/-! ### `splitLeaf` identity on a whole forest -/

lemma map_splitLeaf_id_of_not_mem (s1 s2 f1 f2 : ℕ) (ts : List HuffTree)
    (h : ∀ t ∈ ts, s1 ∉ alphabet t) : ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2) = ts := by
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    have h_t : s1 ∉ alphabet t := h t (by simp)
    have h_ts : ∀ t' ∈ ts, s1 ∉ alphabet t' := fun t' ht' => h t' (by simp [ht'])
    simp [splitLeaf_eq_of_z_not_mem t s1 s1 s2 f1 f2 h_t, ih h_ts]

/-! ### Special case for `optimum_huffman` -/

/--
Given a forest `rest` where `s1` appears only as `htLeaf s1 (f1+f2)` (the combined leaf),
we have the commutation:

`splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2`
`= huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest)`

Requires: `s1 ∉ alphabet t` for all `t ∈ rest`, so that `splitLeaf` does nothing on `rest`.
-/
theorem splitLeaf_huffman_commute (s1 s2 f1 f2 : ℕ) (rest : List HuffTree)
    (h_s1_notin_rest : ∀ t ∈ rest, s1 ∉ alphabet t) :
    splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2
    = huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest) := by
  let LF := htLeaf s1 (f1+f2)
  let IF := htInner (htLeaf s1 f1) (htLeaf s2 f2)
  -- rootFreq is preserved for LF itself (both sides = f1+f2)
  have h_LF_rf : rootFreq (splitLeaf LF s1 s1 s2 f1 f2) = rootFreq LF := by
    simp [LF, splitLeaf, rootFreq]
  -- rootFreq is preserved for rest (splitLeaf is identity since s1 ∉ alphabet)
  have h_rest_rf : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t := by
    intro t ht
    have h_id : splitLeaf t s1 s1 s2 f1 f2 = t :=
      splitLeaf_eq_of_z_not_mem t s1 s1 s2 f1 f2 (h_s1_notin_rest t ht)
    rw [h_id]
  -- rootFreq preserved for the whole insortTree forest
  have h_rf_forest : ∀ t ∈ insortTree LF rest,
      rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
    forall_mem_insortTree (P := λ t => rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t)
      h_LF_rf h_rest_rf
  -- Commutation via the general theorem
  calc
    splitLeaf (huffman (insortTree LF rest)) s1 s1 s2 f1 f2
        = huffman ((insortTree LF rest).map (λ t => splitLeaf t s1 s1 s2 f1 f2)) :=
      splitLeaf_huffman_commute_general (insortTree LF rest) s1 s2 f1 f2
        (by
          -- insortTree LF rest is always nonempty
          intro h_empty
          have : (insortTree LF rest).length = 0 := by simpa [h_empty] using rfl
          -- Actually insortTree returns length = rest.length + 1 ≥ 1
          have h_len : (insortTree LF rest).length = rest.length + 1 := insortTree_length LF rest
          rw [h_len] at this; omega)
        h_rf_forest
    _ = huffman (insortTree (splitLeaf LF s1 s1 s2 f1 f2) (rest.map (λ t => splitLeaf t s1 s1 s2 f1 f2))) := by
      have hLF_rf' : rootFreq (splitLeaf LF s1 s1 s2 f1 f2) = rootFreq LF :=
        h_rf_forest LF ((mem_insortTree LF rest LF).mpr (Or.inl rfl))
      have h_rest_rf' : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
        fun t ht => h_rf_forest t ((mem_insortTree LF rest t).mpr (Or.inr ht))
      rw [map_splitLeaf_insortTree LF rest s1 s2 f1 f2 hLF_rf' h_rest_rf']
    _ = huffman (insortTree IF (rest.map (λ t => splitLeaf t s1 s1 s2 f1 f2))) := by
      simp [LF, IF, splitLeaf]
    _ = huffman (insortTree IF rest) := by
      -- splitLeaf is identity on rest (s1 ∉ alphabet), so the map doesn't change rest
      have h_map_id := map_splitLeaf_id_of_not_mem s1 s2 f1 f2 rest h_s1_notin_rest
      rw [h_map_id]
