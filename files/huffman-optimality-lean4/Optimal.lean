import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.SwapBasic
import CfProofs.Greedy.Huffman.SwapFreqDepth
import CfProofs.Greedy.Huffman.SwapDisjoint
import CfProofs.Greedy.Huffman.MergeLemmas
import CfProofs.Greedy.Huffman.Preservation

open HuffTree

def deepestSiblingPair (t : HuffTree) : ℕ × ℕ :=
  match t with
  | htLeaf s _ => (s, s)
  | htInner l r =>
    match l, r with
    | htLeaf x _, htLeaf y _ => (x, y)
    | htLeaf _ _, _ => deepestSiblingPair r
    | _, htLeaf _ _ => deepestSiblingPair l
    | _, _ => if height l ≥ height r then deepestSiblingPair l else deepestSiblingPair r

lemma deepestSiblingPair_mem1 (t : HuffTree) : (deepestSiblingPair t).1 ∈ alphabet t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, alphabet]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx => cases r with
      | htLeaf y fy => simp [deepestSiblingPair, alphabet]
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htLeaf x fx) (htInner rl rr)) = {x} ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_right {x} ihr
    | htInner ll lr => cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htLeaf y fy)) = alphabet (htInner ll lr) ∪ {y} := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_left {y} ihl
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = (if height (htInner ll lr) ≥ height (htInner rl rr) then deepestSiblingPair (htInner ll lr) else deepestSiblingPair (htInner rl rr)) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htInner rl rr)) = alphabet (htInner ll lr) ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · rw [if_pos h_ge]; exact Finset.mem_union_left (alphabet (htInner rl rr)) ihl
        · rw [if_neg h_ge]; exact Finset.mem_union_right (alphabet (htInner ll lr)) ihr

lemma deepestSiblingPair_mem2 (t : HuffTree) : (deepestSiblingPair t).2 ∈ alphabet t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, alphabet]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx => cases r with
      | htLeaf y fy => simp [deepestSiblingPair, alphabet]
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htLeaf x fx) (htInner rl rr)) = {x} ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_right {x} ihr
    | htInner ll lr => cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htLeaf y fy)) = alphabet (htInner ll lr) ∪ {y} := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_left {y} ihl
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = (if height (htInner ll lr) ≥ height (htInner rl rr) then deepestSiblingPair (htInner ll lr) else deepestSiblingPair (htInner rl rr)) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htInner rl rr)) = alphabet (htInner ll lr) ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · rw [if_pos h_ge]; exact Finset.mem_union_left (alphabet (htInner rl rr)) ihl
        · rw [if_neg h_ge]; exact Finset.mem_union_right (alphabet (htInner ll lr)) ihr

lemma depthOf_getD_inner_of_mem_left {s : ℕ} {l r : HuffTree} (h : s ∈ alphabet l) :
    (depthOf s (htInner l r)).getD 0 = (depthOf s l).getD 0 + 1 := by
  have ⟨d, hd⟩ := depthOf_some_of_mem s l h
  simp [depthOf, hd]

lemma depthOf_getD_inner_of_mem_right {s : ℕ} {l r : HuffTree} (h : s ∈ alphabet r) (h_not : s ∉ alphabet l) :
    (depthOf s (htInner l r)).getD 0 = (depthOf s r).getD 0 + 1 := by
  have ⟨d, hd⟩ := depthOf_some_of_mem s r h
  simp [depthOf, depthOf_none_of_not_mem s l h_not, hd]

lemma deepestSiblingPair_depth (t : HuffTree) (h_cons : consistent t) :
    (depthOf (deepestSiblingPair t).1 t).getD 0 = height t ∧ (depthOf (deepestSiblingPair t).2 t).getD 0 = height t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, depthOf, height]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy =>
        simp [deepestSiblingPair, height]
        have hx : (depthOf x (htInner (htLeaf x fx) (htLeaf y fy))).getD 0 = 1 := by
          simp [depthOf, Option.getD]
        have hy : (depthOf y (htInner (htLeaf x fx) (htLeaf y fy))).getD 0 = 1 := by
          by_cases h_eq : x = y
          · subst h_eq; simp [depthOf, Option.getD]
          · simp [depthOf, h_eq, Option.getD]
        exact And.intro hx hy
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by
          simp [deepestSiblingPair]
        have h_height : height (htInner (htLeaf x fx) (htInner rl rr)) = height (htInner rl rr) + 1 := by
          simp [height]
        rw [h_dsp, h_height]
        rcases ihr hcr with ⟨h1, h2⟩
        have h_mem1 : (deepestSiblingPair (htInner rl rr)).1 ∈ alphabet (htInner rl rr) :=
          deepestSiblingPair_mem1 (htInner rl rr)
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        have h_not_mem_l1 : (deepestSiblingPair (htInner rl rr)).1 ∉ alphabet (htLeaf x fx) := by
          intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem1⟩; rw [h_empty] at hi; simp at hi
        have h_mem2 : (deepestSiblingPair (htInner rl rr)).2 ∈ alphabet (htInner rl rr) :=
          deepestSiblingPair_mem2 (htInner rl rr)
        have h_not_mem_l2 : (deepestSiblingPair (htInner rl rr)).2 ∉ alphabet (htLeaf x fx) := by
          intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem2⟩; rw [h_empty] at hi; simp at hi
        constructor
        · rw [depthOf_getD_inner_of_mem_right h_mem1 h_not_mem_l1, h1]
        · rw [depthOf_getD_inner_of_mem_right h_mem2 h_not_mem_l2, h2]
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by
          simp [deepestSiblingPair]
        have h_height : height (htInner (htInner ll lr) (htLeaf y fy)) = height (htInner ll lr) + 1 := by
          simp [height]
        rw [h_dsp, h_height]
        rcases ihl hcl with ⟨h1, h2⟩
        have h_mem1 : (deepestSiblingPair (htInner ll lr)).1 ∈ alphabet (htInner ll lr) :=
          deepestSiblingPair_mem1 (htInner ll lr)
        have h_mem2 : (deepestSiblingPair (htInner ll lr)).2 ∈ alphabet (htInner ll lr) :=
          deepestSiblingPair_mem2 (htInner ll lr)
        constructor
        · rw [depthOf_getD_inner_of_mem_left h_mem1, h1]
        · rw [depthOf_getD_inner_of_mem_left h_mem2, h2]
      | htInner rl rr =>
        have h_height : height (htInner (htInner ll lr) (htInner rl rr)) = max (height (htInner ll lr)) (height (htInner rl rr)) + 1 := by
          simp [height]
        rw [h_height]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = deepestSiblingPair (htInner ll lr) := by
            simp [deepestSiblingPair, h_ge]
          have h_max : max (height (htInner ll lr)) (height (htInner rl rr)) = height (htInner ll lr) := by
            simp [h_ge]
          rw [h_dsp, h_max]
          rcases ihl hcl with ⟨h1, h2⟩
          have h_mem1 : (deepestSiblingPair (htInner ll lr)).1 ∈ alphabet (htInner ll lr) :=
            deepestSiblingPair_mem1 (htInner ll lr)
          have h_mem2 : (deepestSiblingPair (htInner ll lr)).2 ∈ alphabet (htInner ll lr) :=
            deepestSiblingPair_mem2 (htInner ll lr)
          constructor
          · rw [depthOf_getD_inner_of_mem_left h_mem1, h1]
          · rw [depthOf_getD_inner_of_mem_left h_mem2, h2]
        · have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by
            simp [deepestSiblingPair, h_ge]
          have h_max : max (height (htInner ll lr)) (height (htInner rl rr)) = height (htInner rl rr) :=
            Nat.max_eq_right (by omega)
          rw [h_dsp, h_max]
          rcases ihr hcr with ⟨h1, h2⟩
          have h_mem1 : (deepestSiblingPair (htInner rl rr)).1 ∈ alphabet (htInner rl rr) :=
            deepestSiblingPair_mem1 (htInner rl rr)
          have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
          have h_not_mem_l1 : (deepestSiblingPair (htInner rl rr)).1 ∉ alphabet (htInner ll lr) := by
            intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem1⟩; rw [h_empty] at hi; simp at hi
          have h_mem2 : (deepestSiblingPair (htInner rl rr)).2 ∈ alphabet (htInner rl rr) :=
            deepestSiblingPair_mem2 (htInner rl rr)
          have h_not_mem_l2 : (deepestSiblingPair (htInner rl rr)).2 ∉ alphabet (htInner ll lr) := by
            intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem2⟩; rw [h_empty] at hi; simp at hi
          constructor
          · rw [depthOf_getD_inner_of_mem_right h_mem1 h_not_mem_l1, h1]
          · rw [depthOf_getD_inner_of_mem_right h_mem2 h_not_mem_l2, h2]

lemma deepestSiblingPair_areSiblings (t : HuffTree) (h_cons : consistent t)
    (h_height : height t ≥ 1) :
    areSiblings (deepestSiblingPair t).1 (deepestSiblingPair t).2 t := by
  induction t with
  | htLeaf s f => simp [height] at h_height
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy => exact areSiblings.here (a := x) (b := y) fx fy
      | htInner rl rr =>
        have hh_r : height (htInner rl rr) ≥ 1 := by simp [height]
        have hh := ihr hcr hh_r
        exact areSiblings.inRight (htLeaf x fx) (htInner rl rr) hh
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have hh_l : height (htInner ll lr) ≥ 1 := by simp [height]
        have hh := ihl hcl hh_l
        exact areSiblings.inLeft (htInner ll lr) (htLeaf y fy) hh
      | htInner rl rr =>
        have hh_l : height (htInner ll lr) ≥ 1 := by simp [height]
        have hh_r : height (htInner rl rr) ≥ 1 := by simp [height]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · have hh := ihl hcl hh_l
          simpa [deepestSiblingPair, h_ge] using
            areSiblings.inLeft (htInner ll lr) (htInner rl rr) hh
        · have hh := ihr hcr hh_r
          simpa [deepestSiblingPair, h_ge] using
            areSiblings.inRight (htInner ll lr) (htInner rl rr) hh

lemma areSiblings_exchangeLeft (t : HuffTree) (a x y : ℕ) (h_sib : areSiblings x y t)
    (h_ne_ax : a ≠ x) (h_ne_ay : a ≠ y) (h_ne_xy : x ≠ y) : areSiblings a y (swapLeaves a x t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, h_ne_ax.symm, h_ne_ay.symm, h_ne_xy.symm]
    refine areSiblings.here (a := a) (b := y) ?_ ?_ <;> simp
  | here' fa fb =>
    simp [swapLeaves, h_ne_ax.symm, h_ne_ay.symm, h_ne_xy, h_ne_xy.symm]
    refine areSiblings.here' (a := a) (b := y) ?_ ?_ <;> simp
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma areSiblings_exchangeRight (t : HuffTree) (a b x : ℕ) (h_sib : areSiblings a x t)
    (h_ne_ba : b ≠ a) (h_ne_bx : b ≠ x) (h_ne_ax : a ≠ x) : areSiblings a b (swapLeaves b x t) := by
  induction h_sib with
  | here fa fx =>
    simp [swapLeaves, h_ne_bx.symm, h_ne_ba.symm, h_ne_ax]
    refine areSiblings.here (a := a) (b := b) ?_ ?_ <;> simp
  | here' fa fx =>
    simp [swapLeaves, h_ne_bx.symm, h_ne_ba.symm, h_ne_ax, h_ne_ax.symm]
    refine areSiblings.here' (a := a) (b := b) ?_ ?_ <;> simp
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma areSiblings_replaceFreq (t : HuffTree) (a b sym freq : ℕ) (h_sib : areSiblings a b t) :
    areSiblings a b (replaceFreq sym freq t) := by
  induction h_sib with
  | here fa fb =>
    simp [replaceFreq]; split <;> split <;> apply areSiblings.here
  | here' fa fb =>
    simp [replaceFreq]; split <;> split <;> apply areSiblings.here'
  | inLeft l r h ih =>
    simp [replaceFreq]; exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [replaceFreq]; exact areSiblings.inRight _ _ ih

lemma areSiblings_swapFreqs_preserved (t : HuffTree) (a b x y : ℕ) (h_sib : areSiblings a b t) :
    areSiblings a b (swapFreqs x y t) := by
  dsimp [swapFreqs]
  apply areSiblings_replaceFreq _ _ _ _ _ (areSiblings_replaceFreq _ _ _ _ _ h_sib)

lemma areSiblings_ne (t : HuffTree) (a b : ℕ) (h_cons : consistent t) (h_sib : areSiblings a b t) : a ≠ b := by
  induction h_sib with
  | here fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    intro heq; subst heq
    simp [alphabet, Finset.disjoint_iff_inter_eq_empty] at hd
  | here' fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    intro heq; subst heq
    simp [alphabet, Finset.disjoint_iff_inter_eq_empty] at hd
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, _, _⟩
    exact ih hcl
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨_, hcr, _⟩
    exact ih hcr

private lemma areSiblings_swapLeaves_of_ne {a b z w : ℕ} {t : HuffTree}
    (h_sib : areSiblings a b t) (hz_ne_a : z ≠ a) (hz_ne_b : z ≠ b)
    (hw_ne_a : w ≠ a) (hw_ne_b : w ≠ b) : areSiblings a b (swapLeaves z w t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, Ne.symm hz_ne_a, Ne.symm hz_ne_b, hw_ne_a.symm, hw_ne_b.symm]
    exact areSiblings.here (a := a) (b := b) fa fb
  | here' fa fb =>
    simp [swapLeaves, Ne.symm hz_ne_a, Ne.symm hz_ne_b, hw_ne_a.symm, hw_ne_b.symm]
    exact areSiblings.here' (a := a) (b := b) fa fb
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma depthOf_getD_le_height (t : HuffTree) (s : ℕ) : (depthOf s t).getD 0 ≤ height t := by
  induction t with
  | htLeaf sym f => simp [depthOf, height]; split <;> simp
  | htInner l r ihl ihr =>
    simp [depthOf, height]
    cases h_l : depthOf s l with
    | none =>
      simp [h_l]
      cases h_r : depthOf s r with
      | none => simp
      | some d =>
        simp [h_r]
        have hd : d ≤ height r := by simpa [h_r] using ihr
        omega
    | some d =>
        simp [h_l]
        have hd : d ≤ height l := by simpa [h_l] using ihl
        omega

lemma rootFreq_ge_freqOf (t : HuffTree) (s : ℕ) : rootFreq t ≥ freqOf s t := by
  induction t with
  | htLeaf sym f => simp [rootFreq, freqOf]; split <;> omega
  | htInner l r ihl ihr => simp [rootFreq, freqOf]; omega

lemma optimum_leaf (s f : ℕ) (h_f_pos : f > 0) : optimum (htLeaf s f) := by
  refine ⟨by simp [consistent], ?_, ?_⟩
  · simp [alphabet, freqOf, h_f_pos]
  · intro u _ h_sameFreqs
    simpa [cost] using cost_nonneg u

lemma rootFreq_ge_freqOf_add (t : HuffTree) (a b : ℕ) (h_ne : a ≠ b) (h_cons : consistent t) :
    rootFreq t ≥ freqOf a t + freqOf b t := by
  induction t with
  | htLeaf s f =>
    simp [rootFreq, freqOf]
    by_cases h_a : s = a
    · subst h_a; simp [h_ne.symm]; omega
    · by_cases h_b : s = b
      · subst h_b; simp [h_ne]; omega
      · simp [h_a, h_b]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [rootFreq, freqOf]
    have h1 : rootFreq l ≥ freqOf a l + freqOf b l := ihl hcl
    have h2 : rootFreq r ≥ freqOf a r + freqOf b r := ihr hcr
    omega

lemma optimum_two_distinct_leaves (sa fa sb fb : ℕ) (h_ne : sa ≠ sb) (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) :
    optimum (htInner (htLeaf sa fa) (htLeaf sb fb)) := by
  have h_ne' : sb ≠ sa := Ne.symm h_ne
  have h_pos : ∀ s ∈ alphabet (htInner (htLeaf sa fa) (htLeaf sb fb)), freqOf s (htInner (htLeaf sa fa) (htLeaf sb fb)) > 0 := by
    intro s hs
    simp [alphabet, Finset.mem_insert, Finset.mem_singleton] at hs
    rcases hs with (rfl | rfl)
    · simp [freqOf, h_ne', h_fa_pos]
    · simp [freqOf, h_ne, h_fb_pos]
  refine ⟨by simp [consistent, alphabet, h_ne], h_pos, ?_⟩
  intro u h_cons_u h_sameFreqs
  have h_fa : freqOf sa u = fa := by
    simpa [freqOf, h_ne'] using (h_sameFreqs sa).symm
  have h_fb : freqOf sb u = fb := by
    simpa [freqOf, h_ne] using (h_sameFreqs sb).symm
  simp [cost]
  induction u with
  | htLeaf sym f =>
    simp [freqOf] at h_fa h_fb
    split at h_fa <;> split at h_fb <;> omega
  | htInner l r ihl ihr =>
    rw [cost]
    have h_root : rootFreq l + rootFreq r ≥ fa + fb := by
      simp [freqOf] at h_fa h_fb
      have h_l : rootFreq l ≥ freqOf sa l + freqOf sb l :=
        rootFreq_ge_freqOf_add l sa sb h_ne (by rcases h_cons_u with ⟨hcl, _, _⟩; exact hcl)
      have h_r : rootFreq r ≥ freqOf sa r + freqOf sb r :=
        rootFreq_ge_freqOf_add r sa sb h_ne (by rcases h_cons_u with ⟨_, hcr, _⟩; exact hcr)
      omega
    have h_cost_nonneg : cost l + cost r ≥ 0 := by
      have hl := cost_nonneg l; have hr := cost_nonneg r; omega
    have := add_le_add h_cost_nonneg h_root
    simpa [add_comm, add_left_comm, add_assoc, add_zero] using this
-- swapLeaves is commutative (a↔b = b↔a)
private lemma swapLeaves_comm (a b : ℕ) (t : HuffTree) : swapLeaves a b t = swapLeaves b a t := by
  induction t with
  | htLeaf s f =>
    dsimp [swapLeaves]
    by_cases h1 : s = a
    · rw [h1]
      by_cases h2 : a = b
      · rw [h2]
      · simp [h2]
    · by_cases h2 : s = b
      · rw [h2]; simp [h1, Ne.symm h1]
      · simp [h1, h2]
  | htInner l r ihl ihr =>
    simp [swapLeaves, ihl, ihr]

-- Swap the sibling order: areSiblings a b t → areSiblings b a (swapLeaves a b t)
private lemma areSiblings_swap_siblings {a b : ℕ} {t : HuffTree} (h_sib : areSiblings a b t) (h_ne : a ≠ b) :
    areSiblings b a (swapLeaves a b t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, h_ne, h_ne.symm]
    exact areSiblings.here fa fb
  | here' fa fb =>
    simp [swapLeaves, h_ne, h_ne.symm]
    exact areSiblings.here' fa fb
  | inLeft l r h ih => simp [swapLeaves]; exact areSiblings.inLeft _ _ ih
  | inRight l r h ih => simp [swapLeaves]; exact areSiblings.inRight _ _ ih

-- freqOf merge lemma when merge target is one of the siblings (z = a), relaxes hz_fresh
private lemma freqOf_mergePair_same_sibling (t : HuffTree) (b z s : ℕ)
    (h_sib : areSiblings z b t) (h_cons : consistent t) (hz_ne_b : z ≠ b) :
    freqOf s (mergePair z b z (freqOf z t + freqOf b t) t) =
    if s = z then freqOf z t + freqOf b t else if s = b then 0 else freqOf s t := by
  induction h_sib with
  | here fa fb =>
    -- t = htInner (htLeaf z fa) (htLeaf b fb)
    have h_freq_sum : freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf z fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (fa + fb) (htInner (htLeaf z fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      simp [mergePair, hz_ne_b]
    have h_freq_sum : freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf z fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                                        freqOf b (htInner (htLeaf z fa) (htLeaf b fb)))
                                        (htInner (htLeaf z fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp [hz_ne_b]
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsb : s = b
      · subst s; simp [hz_ne_b]
      · have h_freq_s : freqOf s (htInner (htLeaf z fa) (htLeaf b fb)) = 0 := by
          simp [freqOf, hsz, hsb, Ne.symm hsz, Ne.symm hsb]
        simp [hsz, hsb, h_freq_s]
  | here' fa fb =>
    have h_freq_sum : freqOf z (htInner (htLeaf b fb) (htLeaf z fa)) +
                     freqOf b (htInner (htLeaf b fb) (htLeaf z fa)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (freqOf z (htInner (htLeaf b fb) (htLeaf z fa)) +
                                        freqOf b (htInner (htLeaf b fb) (htLeaf z fa)))
                                        (htInner (htLeaf b fb) (htLeaf z fa)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp [hz_ne_b]
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsb : s = b
      · subst s; simp [hz_ne_b]
      · have h_freq_s : freqOf s (htInner (htLeaf b fb) (htLeaf z fa)) = 0 := by
          simp [freqOf, hsz, hsb, Ne.symm hsz, Ne.symm hsb]
        simp [hsz, hsb, h_freq_s]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨hz_l, hb_l⟩
    have hz_r : z ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hz_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_zr : freqOf z r = 0 := freqOf_eq_zero_of_not_mem _ _ hz_r
    have h_freq_br : freqOf b r = 0 := freqOf_eq_zero_of_not_mem _ _ hb_r
    cases l with
    | htLeaf _ _ => exfalso; cases h_sib_l
    | htInner ll lr =>
      -- t = htInner (htInner ll lr) r; freqOf z r = freqOf b r = 0, so sum reduces to l's sum
      have h_freq_sum : freqOf z (htInner (htInner ll lr) r) + freqOf b (htInner (htInner ll lr) r) =
                       freqOf z (htInner ll lr) + freqOf b (htInner ll lr) := by
        simp [freqOf, h_freq_zr, h_freq_br]
      rw [h_freq_sum]
      have h_merge_r : mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r = r :=
        mergePair_eq_self_of_not_mem z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r hz_r hb_r
      have h_freq_l := ih hcl
      have h_mp : mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr))
                                 (htInner (htInner ll lr) r) =
                 htInner (mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) (htInner ll lr))
                        (mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r) := by
        delta mergePair; simp
      rw [h_mp, h_merge_r]
      conv => lhs; rw [freqOf]
      rw [h_freq_l]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zr]
      · by_cases hsb : s = b
        · subst s; simp [h_freq_br]
        · simp [hsz, hsb, freqOf]
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨hz_r, hb_r⟩
    have hz_l : z ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hz_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_zl : freqOf z l = 0 := freqOf_eq_zero_of_not_mem _ _ hz_l
    have h_freq_bl : freqOf b l = 0 := freqOf_eq_zero_of_not_mem _ _ hb_l
    cases r with
    | htLeaf _ _ => exfalso; cases h_sib_r
    | htInner rl rr =>
      have h_freq_sum : freqOf z (htInner l (htInner rl rr)) + freqOf b (htInner l (htInner rl rr)) =
                       freqOf z (htInner rl rr) + freqOf b (htInner rl rr) := by
        simp [freqOf, h_freq_zl, h_freq_bl]
      rw [h_freq_sum]
      have h_merge_l : mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l = l :=
        mergePair_eq_self_of_not_mem z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l hz_l hb_l
      have h_freq_r := ih hcr
      have h_mp : mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr))
                                 (htInner l (htInner rl rr)) =
                 htInner (mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l)
                        (mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) (htInner rl rr)) := by
        delta mergePair; simp
      rw [h_mp, h_merge_l]
      conv => lhs; rw [freqOf]
      rw [h_freq_r]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zl]
      · by_cases hsb : s = b
        · subst s; simp [h_freq_bl]
        · simp [hsz, hsb, freqOf]

-- NEW: consistent merge when merge target is one of the siblings (z = a)
-- Relaxes hz_fresh from consistent_mergePair_of_areSiblings
private lemma consistent_mergePair_same_sibling (t : HuffTree) (b z fz : ℕ)
    (h_sib : areSiblings z b t) (h_cons : consistent t) (hz_ne_b : z ≠ b) :
    consistent (mergePair z b z fz t) := by
  induction h_sib with
  | here fa fb => simp [mergePair, consistent]
  | here' fa fb => simp [mergePair, consistent]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨hz_l, hb_l⟩
    -- z is in l (as sibling), so z ∉ r by consistency
    have hz_not_r : z ∉ alphabet r := by
      intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
      rw [h_empty] at hi; simp at hi
    have hb_not_r : b ∉ alphabet r := by
      intro hbr; have hi := Finset.mem_inter.mpr ⟨hb_l, hbr⟩
      rw [h_empty] at hi; simp at hi
    have h_merge_r : mergePair z b z fz r = r :=
      mergePair_eq_self_of_not_mem z b z fz r hz_not_r hb_not_r
    have h_l : consistent (mergePair z b z fz l) := ih hcl
    have h_disjoint_merge : Disjoint (alphabet (mergePair z b z fz l)) (alphabet r) := by
      have h_sub : alphabet (mergePair z b z fz l) ⊆ alphabet l ∪ {z} :=
        alphabet_mergePair_subset z b z fz l
      have h_disj_sup : Disjoint (alphabet l ∪ {z}) (alphabet r) := by
        rw [Finset.disjoint_union_left]
        exact ⟨hd, by rw [Finset.disjoint_singleton_left]; exact hz_not_r⟩
      exact Finset.disjoint_of_subset_left h_sub h_disj_sup
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, h_merge_r, consistent]
      exact ⟨h_l, hcr, h_disjoint_merge⟩
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨hz_r, hb_r⟩
    have hz_not_l : z ∉ alphabet l := by
      intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
      rw [h_empty] at hi; simp at hi
    have hb_not_l : b ∉ alphabet l := by
      intro hbl; have hi := Finset.mem_inter.mpr ⟨hbl, hb_r⟩
      rw [h_empty] at hi; simp at hi
    have h_merge_l : mergePair z b z fz l = l :=
      mergePair_eq_self_of_not_mem z b z fz l hz_not_l hb_not_l
    have h_r : consistent (mergePair z b z fz r) := ih hcr
    have h_disjoint_merge : Disjoint (alphabet l) (alphabet (mergePair z b z fz r)) := by
      have h_sub : alphabet (mergePair z b z fz r) ⊆ alphabet r ∪ {z} :=
        alphabet_mergePair_subset z b z fz r
      have h_disj_sup : Disjoint (alphabet l) (alphabet r ∪ {z}) := by
        rw [Finset.disjoint_union_right]
        exact ⟨hd, by rw [Finset.disjoint_singleton_right]; exact hz_not_l⟩
      exact Finset.disjoint_of_subset_right h_sub h_disj_sup
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, h_merge_l, consistent]
      exact ⟨hcl, h_r, h_disjoint_merge⟩

-- Isabelle-style splitLeaf: keep z as left child, add b as right child
private lemma mem_alphabet_splitLeaf_of_ne (t : HuffTree) (z b fa fb x : ℕ) (hx_ne_z : x ≠ z) (hx_ne_b : x ≠ b) :
    x ∈ alphabet (splitLeaf t z z b fa fb) → x ∈ alphabet t := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, alphabet, hx_ne_z, hx_ne_b]
    · simp [splitLeaf, alphabet, hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, alphabet, Finset.mem_union]
    intro h
    rcases h with (h | h)
    · exact Or.inl (ihl h)
    · exact Or.inr (ihr h)

private lemma freqOf_splitLeaf_of_ne (t : HuffTree) (z b fa fb x : ℕ) (hx_ne_z : x ≠ z) (hx_ne_b : x ≠ b) :
    freqOf x (splitLeaf t z z b fa fb) = freqOf x t := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, freqOf, hx_ne_z, hx_ne_b, Ne.symm hx_ne_z, Ne.symm hx_ne_b]
    · simp [splitLeaf, freqOf, hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, freqOf, ihl, ihr]

private lemma freqOf_splitLeaf_left (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    freqOf z (splitLeaf t z z b fa fb) = fa := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    have hz_sym : z = sym := by simpa [alphabet] using hz_in
    subst hz_sym
    simp [splitLeaf, freqOf, hz_ne_b, hz_ne_b.symm, add_zero]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [splitLeaf, freqOf]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r]
      have hz_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hz_not_r
      rw [hz_freq_r, add_zero]
      apply ihl hcl hz_l (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l]
      have hz_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hz_not_l
      rw [hz_freq_l, zero_add]
      apply ihr hcr hz_r (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b

private lemma freqOf_splitLeaf_right (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    freqOf b (splitLeaf t z z b fa fb) = fb := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    have hz_sym : z = sym := by simpa [alphabet] using hz_in
    subst hz_sym
    simp [splitLeaf, freqOf, hz_ne_b, hz_ne_b.symm, add_zero]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [splitLeaf, freqOf]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r]
      have hb_freq_r : freqOf b r = 0 := freqOf_eq_zero_of_not_mem b r (by intro h; apply hb_not; simp [alphabet, h])
      rw [hb_freq_r, add_zero]
      apply ihl hcl hz_l (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l]
      have hb_freq_l : freqOf b l = 0 := freqOf_eq_zero_of_not_mem b l (by intro h; apply hb_not; simp [alphabet, h])
      rw [hb_freq_l, zero_add]
      apply ihr hcr hz_r (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b

private lemma consistent_splitLeaf_v2 (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    consistent (splitLeaf t z z b fa fb) := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, consistent, alphabet, hz_ne_b]
    · simp [splitLeaf, consistent, hz]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    have hb_not_l : b ∉ alphabet l := by intro h; apply hb_not; simp [alphabet, h]
    have hb_not_r : b ∉ alphabet r := by intro h; apply hb_not; simp [alphabet, h]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by
      simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [h_empty] at hi; simp at hi
      have h_split_r : splitLeaf r z z b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r
      rw [splitLeaf, consistent, h_split_r]
      have h_l := ihl hcl hz_l hb_not_l hz_ne_b
      have h_disjoint : Disjoint (alphabet (splitLeaf l z z b fa fb)) (alphabet r) := by
        rw [Finset.disjoint_iff_inter_eq_empty]
        by_contra h_ne
        have h_nonempty := Finset.nonempty_iff_ne_empty.mpr h_ne
        rcases h_nonempty with ⟨s, hs⟩
        rcases Finset.mem_inter.mp hs with ⟨hs_lsplit, hs_r⟩
        by_cases hsb : s = b
        · subst s; apply hb_not; simp [alphabet, hs_r]
        · by_cases hsz : s = z
          · subst s; exact hz_not_r hs_r
          · have hs_l : s ∈ alphabet l :=
              mem_alphabet_splitLeaf_of_ne l z b fa fb s hsz hsb hs_lsplit
            have hi := Finset.mem_inter.mpr ⟨hs_l, hs_r⟩
            rw [h_empty] at hi; simp at hi
      exact And.intro h_l (And.intro hcr h_disjoint)
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [h_empty] at hi; simp at hi
      have h_split_l : splitLeaf l z z b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l
      rw [splitLeaf, consistent, h_split_l]
      have h_r := ihr hcr hz_r hb_not_r hz_ne_b
      have h_disjoint : Disjoint (alphabet l) (alphabet (splitLeaf r z z b fa fb)) := by
        rw [Finset.disjoint_iff_inter_eq_empty]
        by_contra h_ne
        have h_nonempty := Finset.nonempty_iff_ne_empty.mpr h_ne
        rcases h_nonempty with ⟨s, hs⟩
        rcases Finset.mem_inter.mp hs with ⟨hs_l, hs_rsplit⟩
        by_cases hsb : s = b
        · subst s; apply hb_not; simp [alphabet, hs_l]
        · by_cases hsz : s = z
          · subst s; exact hz_not_l hs_l
          · have hs_r : s ∈ alphabet r :=
              mem_alphabet_splitLeaf_of_ne r z b fa fb s hsz hsb hs_rsplit
            have hi := Finset.mem_inter.mpr ⟨hs_l, hs_r⟩
            rw [h_empty] at hi; simp at hi
      exact And.intro hcl (And.intro h_r h_disjoint)

theorem optimum_splitLeaf (t : HuffTree) (z b fa fb : ℕ)
    (h_opt : optimum t) (h_z_in : z ∈ alphabet t)
    (hb_not_mem : b ∉ alphabet t) (hz_ne_b : z ≠ b)
    (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) (h_fa_le_fb : fa ≤ fb)
    (h_fa_min : ∀ s ∈ alphabet t, fa ≤ freqOf s t)
    (h_fb_min : ∀ s ∈ alphabet t, s ≠ z → fb ≤ freqOf s t)
    (h_sum : freqOf z t = fa + fb) :
    optimum (splitLeaf t z z b fa fb) := by
  rcases h_opt with ⟨h_cons_t, h_pos_t, h_opt_t⟩
  have hb_fb_t : freqOf b t = 0 := freqOf_eq_zero_of_not_mem b t hb_not_mem
  -- Part 1: consistency
  have h_cons_split : consistent (splitLeaf t z z b fa fb) :=
    consistent_splitLeaf_v2 t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
  -- Part 2: positivity
  have h_pos_split : ∀ s ∈ alphabet (splitLeaf t z z b fa fb), freqOf s (splitLeaf t z z b fa fb) > 0 := by
    intro s hs
    by_cases hsz : s = z
    · subst s; rw [freqOf_splitLeaf_left t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b]; exact h_fa_pos
    · by_cases hsb : s = b
      · subst s; rw [freqOf_splitLeaf_right t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b]; exact h_fb_pos
      · rw [freqOf_splitLeaf_of_ne t z b fa fb s hsz hsb]
        have hs_t : s ∈ alphabet t := mem_alphabet_splitLeaf_of_ne t z b fa fb s hsz hsb hs
        exact h_pos_t s hs_t
  refine ⟨h_cons_split, h_pos_split, ?_⟩
  intro u h_cons_u h_sameFreqs
  -- Strong induction on cost u for pruning zero-frequency symbols
  have h_cost_split_eq : cost (splitLeaf t z z b fa fb) = cost t + fa + fb :=
    cost_splitLeaf_eq t z z b fa fb h_cons_t h_z_in h_sum
  rw [h_cost_split_eq]
  let P (n : ℕ) : Prop := ∀ (v : HuffTree), nodeCount v = n → consistent v →
    sameFreqs (splitLeaf t z z b fa fb) v → cost t + fa + fb ≤ cost v
  have hP : ∀ n, (∀ m < n, P m) → P n := by
    intro n IH v hn h_cons_v h_sameFreqs_v
    have hz_fa_v : freqOf z v = fa := by
      rw [← h_sameFreqs_v z]
      exact freqOf_splitLeaf_left t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
    have hb_fb_v : freqOf b v = fb := by
      rw [← h_sameFreqs_v b]
      exact freqOf_splitLeaf_right t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
    have hz_in_v : z ∈ alphabet v := by
      by_contra! h_not; have h_zero := freqOf_eq_zero_of_not_mem z v h_not
      rw [hz_fa_v] at h_zero; omega
    have hb_in_v : b ∈ alphabet v := by
      by_contra! h_not; have h_zero := freqOf_eq_zero_of_not_mem b v h_not
      rw [hb_fb_v] at h_zero; omega
    have h_height : height v ≥ 1 := by
      by_contra! h_lt
      have h_le : height v = 0 := by omega
      induction v with
      | htLeaf s f =>
        have h_alph : alphabet (htLeaf s f) = {s} := by simp [alphabet]
        rw [h_alph] at hz_in_v hb_in_v
        simp at hz_in_v hb_in_v; subst hz_in_v hb_in_v; exact hz_ne_b rfl
      | htInner l r => simp [height] at h_le
    have h_dsp_sib : areSiblings (deepestSiblingPair v).1 (deepestSiblingPair v).2 v :=
      deepestSiblingPair_areSiblings v h_cons_v h_height
    set x := (deepestSiblingPair v).1 with hx_def
    set y := (deepestSiblingPair v).2 with hy_def
    have h_dsp_sib_xy : areSiblings x y v := by simpa [hx_def, hy_def] using h_dsp_sib
    have hx_in : x ∈ alphabet v := by simpa [hx_def] using deepestSiblingPair_mem1 v
    have hy_in : y ∈ alphabet v := by simpa [hy_def] using deepestSiblingPair_mem2 v
    have h_depth_pair := deepestSiblingPair_depth v h_cons_v
    rcases h_depth_pair with ⟨h_depth_x_raw, h_depth_y_raw⟩
    have h_depth_x : (depthOf x v).getD 0 = height v := by simpa [hx_def] using h_depth_x_raw
    have h_depth_y : (depthOf y v).getD 0 = height v := by simpa [hy_def] using h_depth_y_raw
    have h_depth_z_le_dx : (depthOf z v).getD 0 ≤ (depthOf x v).getD 0 := by
      rw [h_depth_x]; exact depthOf_getD_le_height v z
    have h_depth_b_le_dy : (depthOf b v).getD 0 ≤ (depthOf y v).getD 0 := by
      rw [h_depth_y]; exact depthOf_getD_le_height v b
    have h_depth_z_le_dy : (depthOf z v).getD 0 ≤ (depthOf y v).getD 0 := by
      rw [h_depth_y]; exact depthOf_getD_le_height v z
    have h_depth_b_le_dx : (depthOf b v).getD 0 ≤ (depthOf x v).getD 0 := by
      rw [h_depth_x]; exact depthOf_getD_le_height v b
    -- Merge helper
    have h_merge_conclude (v' : HuffTree) (h_sib_zb : areSiblings z b v') (h_cons_v' : consistent v')
        (h_fz_v' : freqOf z v' = fa) (h_fb_v' : freqOf b v' = fb)
        (h_freq_rel : ∀ s, freqOf s v' = freqOf s (splitLeaf t z z b fa fb))
        (h_cost_v'_le : (cost v' : ℤ) ≤ (cost v : ℤ)) : cost t + fa + fb ≤ cost v := by
      let v'' := mergePair z b z (fa + fb) v'
      have h_cost_v'' : (cost v'' : ℤ) = (cost v' : ℤ) - (fa : ℤ) - (fb : ℤ) :=
        cost_mergePair_of_areSiblings v' z b z fa fb h_sib_zb h_cons_v' hz_ne_b h_fz_v' h_fb_v' rfl
      have h_cons_v'' : consistent v'' :=
        consistent_mergePair_same_sibling v' b z (fa + fb) h_sib_zb h_cons_v' hz_ne_b
      have h_sameFreqs_v'' : sameFreqs t v'' := by
        intro s
        dsimp [v'']
        have h_freq_sum : freqOf z v' + freqOf b v' = fa + fb := by rw [h_fz_v', h_fb_v']
        have h_lemma := freqOf_mergePair_same_sibling v' b z s h_sib_zb h_cons_v' hz_ne_b
        have h_merge_eq : freqOf s (mergePair z b z (fa + fb) v') =
                          freqOf s (mergePair z b z (freqOf z v' + freqOf b v') v') := by
          rw [← h_freq_sum]
        rw [h_merge_eq, h_lemma]
        split_ifs with hsz hsb
        · rw [hsz, h_fz_v', h_fb_v', h_sum]
        · rw [hsb, hb_fb_t]
        · rw [h_freq_rel s, freqOf_splitLeaf_of_ne t z b fa fb s hsz hsb]
      have h_cost_t_le_v'' : cost t ≤ cost v'' := h_opt_t v'' h_cons_v'' h_sameFreqs_v''
      have h_t_le : (cost t : ℤ) ≤ (cost v'' : ℤ) := by exact_mod_cast h_cost_t_le_v''
      have h_goal_ℤ : (cost t : ℤ) + (fa : ℤ) + (fb : ℤ) ≤ (cost v : ℤ) := by linarith
      exact_mod_cast h_goal_ℤ
    -- Case analysis on x, y relative to z, b
    by_cases hxz : x = z
    · -- x=z case
      rw [hxz] at h_dsp_sib_xy hx_in h_depth_x h_depth_z_le_dx h_depth_b_le_dx
      by_cases hyb : y = b
      · rw [hyb] at h_dsp_sib_xy
        have h_freq_rel_v : ∀ s, freqOf s v = freqOf s (splitLeaf t z z b fa fb) :=
          fun s => (h_sameFreqs_v s).symm
        exact h_merge_conclude v h_dsp_sib_xy h_cons_v hz_fa_v hb_fb_v h_freq_rel_v (le_refl _)
      · have hb_ne_y : b ≠ y := Ne.symm hyb
        have hx_ne_y : z ≠ y := areSiblings_ne v z y h_cons_v h_dsp_sib_xy
        by_cases hy_in_t : y ∈ alphabet t
        · -- Standard: swap b↔y
          have h_freq_b_y : freqOf b v ≤ freqOf y v := by
            rw [hb_fb_v]
            have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
            have hy_ne_z : y ≠ z := Ne.symm hx_ne_y
            have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
              freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb
            rw [hy_freq_v, hy_freq_t]
            exact h_fb_min y hy_in_t hy_ne_z
          let v1 := swapFreqs b y (swapLeaves b y v)
          have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
            cost_exchangeLeaf_le v b y h_cons_v hb_in_v hy_in hb_ne_y h_freq_b_y h_depth_b_le_dy
          have h_sib_zb_swap : areSiblings z b (swapLeaves b y v) :=
            areSiblings_exchangeRight v z b y h_dsp_sib_xy (Ne.symm hz_ne_b) hb_ne_y hx_ne_y
          have h_sib_zb_v1 : areSiblings z b v1 :=
            areSiblings_swapFreqs_preserved (swapLeaves b y v) z b b y h_sib_zb_swap
          have h_cons_v1 : consistent v1 := by
            dsimp [v1, swapFreqs]
            apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v))
            apply consistent_replaceFreq b _ (swapLeaves b y v)
            exact consistent_swapLeaves b y v h_cons_v
          have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
            intro s
            have h_ex : freqOf s (swapFreqs b y (swapLeaves b y v)) = freqOf s v :=
              freqOf_exchangeLeaf v b y s hb_ne_y hb_in_v hy_in h_cons_v
            dsimp [v1]; rw [h_ex]; exact (h_sameFreqs_v s).symm
          have h_fz_v1 : freqOf z v1 = fa := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v b y z hb_ne_y hb_in_v hy_in h_cons_v, hz_fa_v]
          have h_fb_v1 : freqOf b v1 = fb := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v b y b hb_ne_y hb_in_v hy_in h_cons_v, hb_fb_v]
          exact h_merge_conclude v1 h_sib_zb_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
        · -- Edge: y ∉ alphabet t, prune z,y and use IH
          have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
          have h_freq_y_v : freqOf y v = 0 := by
            rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hx_ne_y) hyb, h_freq_y_t]
          let v_pruned := mergePair z y z (freqOf z v + freqOf y v) v
          have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
            have h_ne : z ≠ y := hx_ne_y
            have h_lt : nodeCount v_pruned < nodeCount v :=
              nodeCount_mergePair_lt_of_areSiblings v z y z (freqOf z v + freqOf y v) h_dsp_sib_xy h_ne
            omega
          have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
            have h_cost_int : (cost v_pruned : ℤ) = (cost v : ℤ) - (fa : ℤ) := by
              have h := cost_mergePair_of_areSiblings v z y z fa 0 h_dsp_sib_xy h_cons_v hx_ne_y
                hz_fa_v h_freq_y_v (by ring)
              simpa [v_pruned, hz_fa_v, h_freq_y_v, add_zero] using h
            have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
            omega
          have h_cons_pruned : consistent v_pruned :=
            consistent_mergePair_same_sibling v y z (freqOf z v + freqOf y v) h_dsp_sib_xy h_cons_v hx_ne_y
          have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
            intro s
            have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
              dsimp [v_pruned]
              rw [freqOf_mergePair_same_sibling v y z s h_dsp_sib_xy h_cons_v hx_ne_y, hz_fa_v, h_freq_y_v]
              by_cases hsz : s = z
              · subst s; simp [hz_fa_v, h_freq_y_v]
              · by_cases hsy : s = y
                · subst s; simp [hsz, h_freq_y_v]
                · simp [hsz, hsy, hz_fa_v, h_freq_y_v]
            rw [h_freq_pruned, h_sameFreqs_v s]
          have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
          have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
            h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
          omega
    · by_cases hxb : x = b
      · -- x=b case: areSiblings b y v
        rw [hxb] at h_dsp_sib_xy hx_in h_depth_x h_depth_z_le_dx h_depth_b_le_dx
        have hb_ne_y : b ≠ y := areSiblings_ne v b y h_cons_v h_dsp_sib_xy
        by_cases hyz : y = z
        · -- areSiblings b z v, swap b↔z to get z,b order
          rw [hyz] at h_dsp_sib_xy
          -- h_dsp_sib_xy : areSiblings b z v
          let v1 := swapFreqs z b (swapLeaves z b v)
          have h_sib_v1 : areSiblings z b v1 := by
            dsimp [v1]
            have h := areSiblings_swap_siblings h_dsp_sib_xy (Ne.symm hz_ne_b)
            -- h : areSiblings z b (swapLeaves b z v)
            rw [swapLeaves_comm b z v] at h
            exact areSiblings_swapFreqs_preserved (swapLeaves z b v) z b z b h
          have h_cons_v1 : consistent v1 := by
            dsimp [v1, swapFreqs]
            apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v))
            apply consistent_replaceFreq z _ (swapLeaves z b v)
            exact consistent_swapLeaves z b v h_cons_v
          have h_fz_le_fb_v : freqOf z v ≤ freqOf b v := by
            rw [hz_fa_v, hb_fb_v]; exact h_fa_le_fb
          have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
            cost_exchangeLeaf_le v z b h_cons_v hz_in_v hb_in_v hz_ne_b h_fz_le_fb_v h_depth_z_le_dx
          have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
            intro s
            dsimp [v1]
            rw [freqOf_exchangeLeaf v z b s hz_ne_b hz_in_v hb_in_v h_cons_v]
            exact (h_sameFreqs_v s).symm
          have h_fz_v1 : freqOf z v1 = fa := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v z b z hz_ne_b hz_in_v hb_in_v h_cons_v, hz_fa_v]
          have h_fb_v1 : freqOf b v1 = fb := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
          exact h_merge_conclude v1 h_sib_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
        · -- y ≠ z
          have hz_ne_y : z ≠ y := by intro h_eq; apply hyz; exact h_eq.symm
          have hy_ne_b : y ≠ b := Ne.symm hb_ne_y
          by_cases hy_in_t : y ∈ alphabet t
          · -- Standard case: two swaps. v1 = swap z↔b, v2 = swap b↔y on v1
            let v1 := swapFreqs z b (swapLeaves z b v)
            have h_sib_v1 : areSiblings z y v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves z b v) z y z b
                (areSiblings_exchangeLeft v z b y h_dsp_sib_xy hz_ne_b hz_ne_y hb_ne_y)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v))
              apply consistent_replaceFreq z _ (swapLeaves z b v)
              exact consistent_swapLeaves z b v h_cons_v
            have h_fz_le_fb_v : freqOf z v ≤ freqOf b v := by
              rw [hz_fa_v, hb_fb_v]; exact h_fa_le_fb
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v z b h_cons_v hz_in_v hb_in_v hz_ne_b h_fz_le_fb_v h_depth_z_le_dx
            have hy_in_v1 : y ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨y, hy_in, by dsimp [swapSym]; simp [hyz, hy_ne_b]⟩
            have hz_in_v1 : z ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨b, hb_in_v, by dsimp [swapSym]; simp [hz_ne_b]⟩
            have hb_in_v1 : b ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨z, hz_in_v, by dsimp [swapSym]; simp⟩
            -- Depth inequality for second swap: depthOf b v1 ≤ depthOf y v1
            have h_depth_b_y_v1 : (depthOf b v1).getD 0 ≤ (depthOf y v1).getD 0 := by
              have h_dep_b : (depthOf b v1).getD 0 = (depthOf z v).getD 0 := by
                dsimp [v1, swapFreqs]
                rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_at_b z b v hz_ne_b]
              have h_dep_y : (depthOf y v1).getD 0 = (depthOf y v).getD 0 := by
                dsimp [v1, swapFreqs]
                rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z b y v (Ne.symm hz_ne_y) hy_ne_b]
              rw [h_dep_b, h_dep_y, h_depth_y, ← h_depth_x]
              exact h_depth_z_le_dx
            -- Frequency inequality for second swap: freqOf b v1 ≤ freqOf y v1
            have h_freq_b_y_v1 : freqOf b v1 ≤ freqOf y v1 := by
              have h_fb_v1 : freqOf b v1 = fb := by
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
              have h_fy_v1 : freqOf y v1 = freqOf y v := by
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z b y hz_ne_b hz_in_v hb_in_v h_cons_v]
              rw [h_fb_v1, h_fy_v1]
              have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
              have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
                freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hz_ne_y) hy_ne_b
              rw [hy_freq_v, hy_freq_t]
              exact h_fb_min y hy_in_t (Ne.symm hz_ne_y)
            -- Second swap: b↔y
            let v2 := swapFreqs b y (swapLeaves b y v1)
            have h_sib_v2 : areSiblings z b v2 :=
              areSiblings_swapFreqs_preserved (swapLeaves b y v1) z b b y
                (areSiblings_exchangeRight v1 z b y h_sib_v1 (Ne.symm hz_ne_b) hb_ne_y hz_ne_y)
            have h_cons_v2 : consistent v2 := by
              dsimp [v2, swapFreqs]
              apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v1))
              apply consistent_replaceFreq b _ (swapLeaves b y v1)
              exact consistent_swapLeaves b y v1 h_cons_v1
            have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) :=
              cost_exchangeLeaf_le v1 b y h_cons_v1 hb_in_v1 hy_in_v1 hb_ne_y h_freq_b_y_v1 h_depth_b_y_v1
            have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
              intro s
              have h_ex1 : freqOf s v1 = freqOf s v :=
                freqOf_exchangeLeaf v z b s hz_ne_b hz_in_v hb_in_v h_cons_v
              have h_ex2 : freqOf s (swapFreqs b y (swapLeaves b y v1)) = freqOf s v1 :=
                freqOf_exchangeLeaf v1 b y s hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1
              dsimp [v2]; rw [h_ex2, h_ex1]; exact (h_sameFreqs_v s).symm
            have h_fz_v2 : freqOf z v2 = fa := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 b y z hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v z b z hz_ne_b hz_in_v hb_in_v h_cons_v, hz_fa_v]
            have h_fb_v2 : freqOf b v2 = fb := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 b y b hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
            have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
            exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
          · -- Edge: y ∉ alphabet t, prune b,y and use IH
            have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
            have h_freq_y_v : freqOf y v = 0 := by
              rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hz_ne_y) hy_ne_b, h_freq_y_t]
            let v_pruned := mergePair b y b (freqOf b v + freqOf y v) v
            have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
              have h_ne : b ≠ y := hb_ne_y
              have h_lt : nodeCount v_pruned < nodeCount v :=
                nodeCount_mergePair_lt_of_areSiblings v b y b (freqOf b v + freqOf y v) h_dsp_sib_xy h_ne
              omega
            have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
              have h_cost_int : (cost v_pruned : ℤ) = (cost v : ℤ) - (fb : ℤ) := by
                have h := cost_mergePair_of_areSiblings v b y b fb 0 h_dsp_sib_xy h_cons_v hb_ne_y
                  hb_fb_v h_freq_y_v (by ring)
                simpa [v_pruned, hb_fb_v, h_freq_y_v, add_zero] using h
              have h_fb_pos_int : (0 : ℤ) < fb := by exact_mod_cast h_fb_pos
              omega
            have h_cons_pruned : consistent v_pruned :=
              consistent_mergePair_same_sibling v y b (freqOf b v + freqOf y v) h_dsp_sib_xy h_cons_v hb_ne_y
            have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
              intro s
              have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
                dsimp [v_pruned]
                rw [freqOf_mergePair_same_sibling v y b s h_dsp_sib_xy h_cons_v hb_ne_y, hb_fb_v, h_freq_y_v, add_zero]
                by_cases hsb : s = b
                · rw [hsb, if_pos rfl, hb_fb_v]
                · by_cases hsy : s = y
                  · rw [hsy]
                    by_cases hyb : y = b
                    · rw [hyb] at h_freq_y_v; rw [hb_fb_v] at h_freq_y_v; omega
                    · rw [if_neg hyb, if_pos rfl, h_freq_y_v]
                  · rw [if_neg hsb, if_neg hsy]
              rw [h_freq_pruned, h_sameFreqs_v s]
            have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
            have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
              h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
            omega
      · -- x≠z,b case: areSiblings x y v with x∉{z,b}
        have hx_ne_z : x ≠ z := hxz
        have hx_ne_b : x ≠ b := hxb
        have hz_ne_x : z ≠ x := Ne.symm hxz
        have hb_ne_x : b ≠ x := Ne.symm hxb
        have hx_ne_y : x ≠ y := areSiblings_ne v x y h_cons_v h_dsp_sib_xy
        by_cases hyz : y = z
        · -- areSiblings x z v (after rw hyz), swap b↔x to get z,b siblings
          rw [hyz] at h_dsp_sib_xy
          by_cases hx_in_t' : x ∈ alphabet t
          · -- Standard: x ∈ alphabet t, swap b↔x then swap order
            have h_freq_b_x : freqOf b v ≤ freqOf x v := by
              rw [hb_fb_v]
              have hx_freq_v : freqOf x v = freqOf x t := by
                rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              rw [hx_freq_v]
              exact h_fb_min x hx_in_t' hx_ne_z
            have h_depth_b_x : (depthOf b v).getD 0 ≤ (depthOf x v).getD 0 := h_depth_b_le_dx
            -- First swap: b↔x → areSiblings b z (swapLeaves b x v)
            let v1 := swapFreqs b x (swapLeaves b x v)
            have hb_in_v1 : b ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              refine ⟨x, hx_in, ?_⟩
              dsimp [swapSym]; simp [hb_ne_x, hx_ne_b.symm]
            have hz_in_v1 : z ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              refine ⟨z, hz_in_v, ?_⟩
              dsimp [swapSym]; rw [if_neg hz_ne_b, if_neg (Ne.symm hx_ne_z)]
            have h_sib_v1 : areSiblings b z v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves b x v) b z b x
                (areSiblings_exchangeLeft v b x z h_dsp_sib_xy hb_ne_x (Ne.symm hz_ne_b) hx_ne_z)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq x _ (replaceFreq b _ (swapLeaves b x v))
              apply consistent_replaceFreq b _ (swapLeaves b x v)
              exact consistent_swapLeaves b x v h_cons_v
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v b x h_cons_v hb_in_v hx_in hb_ne_x h_freq_b_x h_depth_b_x
            -- Second swap: z↔b to get z,b order
            let v2 := swapFreqs z b (swapLeaves z b v1)
            have h_sib_v2 : areSiblings z b v2 := by
              dsimp [v2]
              have h := areSiblings_swap_siblings h_sib_v1 (Ne.symm hz_ne_b)
              -- h : areSiblings z b (swapLeaves b z v1)
              rw [swapLeaves_comm b z v1] at h
              exact areSiblings_swapFreqs_preserved (swapLeaves z b v1) z b z b h
            have h_cons_v2 : consistent v2 := by
              dsimp [v2, swapFreqs]
              apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v1))
              apply consistent_replaceFreq z _ (swapLeaves z b v1)
              exact consistent_swapLeaves z b v1 h_cons_v1
            have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) := by
              have hb_freq_v1 : freqOf b v1 = fb := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v b x b hb_ne_x hb_in_v hx_in h_cons_v, hb_fb_v]
              have hz_freq_v1 : freqOf z v1 = fa := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v b x z hb_ne_x hb_in_v hx_in h_cons_v, hz_fa_v]
              have h_freq_z_b_v1 : freqOf z v1 ≤ freqOf b v1 := by
                rw [hz_freq_v1, hb_freq_v1]; exact h_fa_le_fb
              have h_depth_z_b_v1 : (depthOf z v1).getD 0 ≤ (depthOf b v1).getD 0 := by
                have h_dep_b : (depthOf b v1).getD 0 = (depthOf x v).getD 0 := by
                  dsimp [v1, swapFreqs]
                  rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_at_a b x v hb_ne_x]
                have h_dep_z : (depthOf z v1).getD 0 = (depthOf z v).getD 0 := by
                  dsimp [v1, swapFreqs]
                  rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is b x z v hz_ne_b (Ne.symm hx_ne_z)]
                rw [h_dep_z, h_dep_b, h_depth_x]
                exact depthOf_getD_le_height v z
              simpa [v2] using cost_exchangeLeaf_le v1 z b h_cons_v1 hz_in_v1 hb_in_v1 hz_ne_b h_freq_z_b_v1 h_depth_z_b_v1
            have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
              intro s
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b s hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x s hb_ne_x hb_in_v hx_in h_cons_v]
              exact (h_sameFreqs_v s).symm
            have h_fz_v2 : freqOf z v2 = fa := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b z hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x z hb_ne_x hb_in_v hx_in h_cons_v, hz_fa_v]
            have h_fb_v2 : freqOf b v2 = fb := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b b hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x b hb_ne_x hb_in_v hx_in h_cons_v, hb_fb_v]
            have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
            exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
          · -- Edge: x ∉ alphabet t, y=z. Both x and z are deepest siblings (same depth).
            -- Swap x↔z (same depth, cost preserved) so z becomes first sibling, then merge into z.
            have h_freq_x_v : freqOf x v = 0 := by
              rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              exact freqOf_eq_zero_of_not_mem x t hx_in_t'
            -- Both x and z are deepest siblings: y=z and y is deepest
            have h_depth_z_eq : (depthOf z v).getD 0 = height v := by
              rw [← hyz]; exact h_depth_y
            have h_depth_x_eq_z : (depthOf x v).getD 0 = (depthOf z v).getD 0 := by
              rw [h_depth_x, h_depth_z_eq]
            have h_depth_x_le_z : (depthOf x v).getD 0 ≤ (depthOf z v).getD 0 := by rw [h_depth_x_eq_z]
            -- Swap x↔z: x (freq 0) into z's position. freq 0 ≤ fa, depth equal → cost non-increasing.
            let v_pre := swapFreqs x z (swapLeaves x z v)
            have h_sib_pre : areSiblings z x v_pre := by
              dsimp [v_pre]
              have h := areSiblings_swap_siblings h_dsp_sib_xy hx_ne_z
              -- h : areSiblings z x (swapLeaves x z v)
              exact areSiblings_swapFreqs_preserved (swapLeaves x z v) z x x z h
            have h_cons_pre : consistent v_pre := by
              dsimp [v_pre, swapFreqs]
              apply consistent_replaceFreq z _ (replaceFreq x _ (swapLeaves x z v))
              apply consistent_replaceFreq x _ (swapLeaves x z v)
              exact consistent_swapLeaves x z v h_cons_v
            have h_cost_pre : (cost v_pre : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v x z h_cons_v hx_in hz_in_v hx_ne_z
                (by rw [h_freq_x_v, hz_fa_v]; omega) h_depth_x_le_z
            have h_fz_pre : freqOf z v_pre = fa := by
              dsimp [v_pre]; rw [freqOf_exchangeLeaf v x z z hx_ne_z hx_in hz_in_v h_cons_v, hz_fa_v]
            have h_fx_pre : freqOf x v_pre = 0 := by
              dsimp [v_pre]; rw [freqOf_exchangeLeaf v x z x hx_ne_z hx_in hz_in_v h_cons_v, h_freq_x_v]
            -- Now z is first sibling, merge into z
            let v_pruned := mergePair z x z (freqOf z v_pre + freqOf x v_pre) v_pre
            have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
              have h_ne : z ≠ x := Ne.symm hx_ne_z
              have h_lt : nodeCount v_pruned < nodeCount v_pre :=
                nodeCount_mergePair_lt_of_areSiblings v_pre z x z (freqOf z v_pre + freqOf x v_pre) h_sib_pre h_ne
              have h_eq_pre : nodeCount v_pre = nodeCount v := by
                dsimp [v_pre, swapFreqs]
                rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
              omega
            have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
              have h_cost_int : (cost v_pruned : ℤ) = (cost v_pre : ℤ) - (fa : ℤ) := by
                have h := cost_mergePair_of_areSiblings v_pre z x z fa 0 (fz := freqOf z v_pre + freqOf x v_pre)
                  h_sib_pre h_cons_pre (Ne.symm hx_ne_z) h_fz_pre h_fx_pre
                  (by rw [h_fz_pre, h_fx_pre, add_zero])
                simpa [v_pruned, add_zero] using h
              have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
              have h_cost_pre_le_v : (cost v_pre : ℤ) ≤ (cost v : ℤ) := h_cost_pre
              omega
            have h_cons_pruned : consistent v_pruned :=
              consistent_mergePair_same_sibling v_pre x z (freqOf z v_pre + freqOf x v_pre)
                h_sib_pre h_cons_pre (Ne.symm hx_ne_z)
            have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
              intro s
              have h_freq_pruned : freqOf s v_pruned = freqOf s v_pre := by
                dsimp [v_pruned]
                rw [freqOf_mergePair_same_sibling v_pre x z s h_sib_pre h_cons_pre (Ne.symm hx_ne_z),
                  h_fz_pre, h_fx_pre, add_zero]
                by_cases hsz : s = z
                · rw [hsz, if_pos rfl, h_fz_pre]
                · by_cases hsx : s = x
                  · rw [hsx]
                    by_cases hxz' : x = z; · exfalso; exact hx_ne_z hxz'
                    rw [if_neg hxz', if_pos rfl, h_fx_pre]
                  · rw [if_neg hsz, if_neg hsx]
              rw [h_freq_pruned]
              dsimp [v_pre]
              rw [freqOf_exchangeLeaf v x z s hx_ne_z hx_in hz_in_v h_cons_v]
              exact h_sameFreqs_v s
            have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
            have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
              h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
            omega
        · -- y ≠ z, can do the standard swap z↔x
          have hz_ne_y : z ≠ y := Ne.symm hyz
          have hy_ne_z : y ≠ z := hyz
          by_cases hx_in_t : x ∈ alphabet t
          · -- x ∈ alphabet t, so freqOf x v ≥ fa. Standard exchange approach.
            have h_freq_z_x : freqOf z v ≤ freqOf x v := by
              rw [hz_fa_v]
              have hx_freq_v : freqOf x v = freqOf x t := by
                rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              rw [hx_freq_v]
              exact h_fa_min x hx_in_t
            -- First swap: z↔x to get z as first sibling
            let v1 := swapFreqs z x (swapLeaves z x v)
            have h_sib_v1 : areSiblings z y v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves z x v) z y z x
                (areSiblings_exchangeLeft v z x y h_dsp_sib_xy hz_ne_x hz_ne_y hx_ne_y)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq x _ (replaceFreq z _ (swapLeaves z x v))
              apply consistent_replaceFreq z _ (swapLeaves z x v)
              exact consistent_swapLeaves z x v h_cons_v
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v z x h_cons_v hz_in_v hx_in hz_ne_x h_freq_z_x h_depth_z_le_dx
            -- Now areSiblings z y v1. Same situation as x=z case.
            by_cases hyb : y = b
            · -- z,b already siblings in v1
              rw [hyb] at h_sib_v1
              have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
                intro s
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                exact (h_sameFreqs_v s).symm
              have h_fz_v1 : freqOf z v1 = fa := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
              have h_fb_v1 : freqOf b v1 = fb := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
              exact h_merge_conclude v1 h_sib_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
            · -- y ≠ b, need second swap b↔y or pruning
              have hb_ne_y : b ≠ y := Ne.symm hyb
              have hy_ne_x : y ≠ x := Ne.symm hx_ne_y
              by_cases hy_in_t : y ∈ alphabet t
              · -- Standard: second swap b↔y on v1
                have hz_in_v1 : z ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  exact ⟨x, hx_in, by dsimp [swapSym]; simp [hz_ne_x]⟩
                have hy_in_v1 : y ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  exact ⟨y, hy_in, by dsimp [swapSym]; simp [hy_ne_z, hy_ne_x]⟩
                have hb_in_v1 : b ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  refine ⟨b, hb_in_v, ?_⟩
                  dsimp [swapSym]
                  simp [Ne.symm hz_ne_b, hb_ne_x]
                -- depth inequality for second swap
                have h_depth_b_y_v1 : (depthOf b v1).getD 0 ≤ (depthOf y v1).getD 0 := by
                  have h_dep_b : (depthOf b v1).getD 0 = (depthOf b v).getD 0 := by
                    dsimp [v1, swapFreqs]
                    rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z x b v (Ne.symm hz_ne_b) hb_ne_x]
                  have h_dep_y : (depthOf y v1).getD 0 = (depthOf y v).getD 0 := by
                    dsimp [v1, swapFreqs]
                    rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z x y v hy_ne_z hy_ne_x]
                  rw [h_dep_b, h_dep_y, h_depth_y, ← h_depth_x]
                  exact h_depth_b_le_dx
                -- frequency inequality for second swap
                have h_freq_b_y_v1 : freqOf b v1 ≤ freqOf y v1 := by
                  have h_fb_v1 : freqOf b v1 = fb := by
                    dsimp [v1]; rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
                  have h_fy_v1 : freqOf y v1 = freqOf y v := by
                    dsimp [v1]; rw [freqOf_exchangeLeaf v z x y hz_ne_x hz_in_v hx_in h_cons_v]
                  rw [h_fb_v1, h_fy_v1]
                  have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
                  have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
                    freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb
                  rw [hy_freq_v, hy_freq_t]
                  exact h_fb_min y hy_in_t hy_ne_z
                -- Second swap
                let v2 := swapFreqs b y (swapLeaves b y v1)
                have h_sib_v2 : areSiblings z b v2 :=
                  areSiblings_swapFreqs_preserved (swapLeaves b y v1) z b b y
                    (areSiblings_exchangeRight v1 z b y h_sib_v1 (Ne.symm hz_ne_b) hb_ne_y hz_ne_y)
                have h_cons_v2 : consistent v2 := by
                  dsimp [v2, swapFreqs]
                  apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v1))
                  apply consistent_replaceFreq b _ (swapLeaves b y v1)
                  exact consistent_swapLeaves b y v1 h_cons_v1
                have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) :=
                  cost_exchangeLeaf_le v1 b y h_cons_v1 hb_in_v1 hy_in_v1 hb_ne_y h_freq_b_y_v1 h_depth_b_y_v1
                have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
                  intro s
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y s hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                  exact (h_sameFreqs_v s).symm
                have h_fz_v2 : freqOf z v2 = fa := by
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y z hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
                have h_fb_v2 : freqOf b v2 = fb := by
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y b hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
                have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
                exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
              · -- y ∉ alphabet t, prune z,y from v1 and use IH
                have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
                have h_freq_y_v1 : freqOf y v1 = 0 := by
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x y hz_ne_x hz_in_v hx_in h_cons_v]
                  rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb, h_freq_y_t]
                have h_fz_v1_val : freqOf z v1 = fa := by
                  dsimp [v1]; rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
                let v_pruned := mergePair z y z (freqOf z v1 + freqOf y v1) v1
                have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                  have h_ne : z ≠ y := hz_ne_y
                  have h_lt : nodeCount v_pruned < nodeCount v1 :=
                    nodeCount_mergePair_lt_of_areSiblings v1 z y z (freqOf z v1 + freqOf y v1) h_sib_v1 h_ne
                  have h_eq_v1 : nodeCount v1 = nodeCount v := by
                    dsimp [v1, swapFreqs]
                    rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
                  omega
                have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
                  have h_cost_int : (cost v_pruned : ℤ) = (cost v1 : ℤ) - (fa : ℤ) := by
                    have h := cost_mergePair_of_areSiblings v1 z y z fa 0 h_sib_v1 h_cons_v1 hz_ne_y
                      h_fz_v1_val h_freq_y_v1 (by ring)
                    simpa [v_pruned, h_fz_v1_val, h_freq_y_v1, add_zero] using h
                  have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
                  have h_cost_v1_le_v : (cost v1 : ℤ) ≤ (cost v : ℤ) := h_cost_v1
                  omega
                have h_cons_pruned : consistent v_pruned :=
                  consistent_mergePair_same_sibling v1 y z (freqOf z v1 + freqOf y v1) h_sib_v1 h_cons_v1 hz_ne_y
                have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                  intro s
                  have h_freq_pruned : freqOf s v_pruned = freqOf s v1 := by
                    dsimp [v_pruned]
                    rw [freqOf_mergePair_same_sibling v1 y z s h_sib_v1 h_cons_v1 hz_ne_y, h_fz_v1_val, h_freq_y_v1, add_zero]
                    by_cases hsz : s = z
                    · rw [hsz, if_pos rfl, h_fz_v1_val]
                    · by_cases hsy : s = y
                      · rw [hsy]
                        by_cases hyz' : y = z
                        · rw [hyz'] at h_freq_y_v1; rw [h_fz_v1_val] at h_freq_y_v1; omega
                        · rw [if_neg hyz', if_pos rfl, h_freq_y_v1]
                      · rw [if_neg hsz, if_neg hsy]
                  rw [h_freq_pruned]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                  exact (h_sameFreqs_v s)
                have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
                have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                  h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
                omega
          · -- Edge: x ∉ alphabet t. Both x,y are deepest siblings (same depth).
            -- Swap x↔y (same depth, cost preserved) so y becomes first sibling, then merge into y.
            have h_freq_x_v : freqOf x v = 0 := by
              rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              exact freqOf_eq_zero_of_not_mem x t hx_in_t
            have h_depth_x_eq_y : (depthOf x v).getD 0 = (depthOf y v).getD 0 := by
              rw [h_depth_x, h_depth_y]
            have h_depth_x_le_y : (depthOf x v).getD 0 ≤ (depthOf y v).getD 0 := by rw [h_depth_x_eq_y]
            by_cases h_freq_y_pos : freqOf y v > 0
            · -- Swap x↔y: x (freq 0) into y's position. freq 0 ≤ freqOf y v, depth equal → cost non-increasing.
              let v_pre := swapFreqs x y (swapLeaves x y v)
              have h_sib_pre : areSiblings y x v_pre := by
                dsimp [v_pre]
                have h := areSiblings_swap_siblings h_dsp_sib_xy hx_ne_y
                exact areSiblings_swapFreqs_preserved (swapLeaves x y v) y x x y h
              have h_cons_pre : consistent v_pre := by
                dsimp [v_pre, swapFreqs]
                apply consistent_replaceFreq y _ (replaceFreq x _ (swapLeaves x y v))
                apply consistent_replaceFreq x _ (swapLeaves x y v)
                exact consistent_swapLeaves x y v h_cons_v
              have h_cost_pre : (cost v_pre : ℤ) ≤ (cost v : ℤ) :=
                cost_exchangeLeaf_le v x y h_cons_v hx_in hy_in hx_ne_y
                  (by rw [h_freq_x_v]; omega) h_depth_x_le_y
              have h_fy_pre : freqOf y v_pre = freqOf y v := by
                dsimp [v_pre]; rw [freqOf_exchangeLeaf v x y y hx_ne_y hx_in hy_in h_cons_v]
              have h_fx_pre : freqOf x v_pre = 0 := by
                dsimp [v_pre]; rw [freqOf_exchangeLeaf v x y x hx_ne_y hx_in hy_in h_cons_v, h_freq_x_v]
              let v_pruned := mergePair y x y (freqOf y v_pre + freqOf x v_pre) v_pre
              have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                have h_ne : y ≠ x := Ne.symm hx_ne_y
                have h_lt : nodeCount v_pruned < nodeCount v_pre :=
                  nodeCount_mergePair_lt_of_areSiblings v_pre y x y (freqOf y v_pre + freqOf x v_pre) h_sib_pre h_ne
                have h_eq_pre : nodeCount v_pre = nodeCount v := by
                  dsimp [v_pre, swapFreqs]
                  rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
                omega
              have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
                have h_cost_int : (cost v_pruned : ℤ) = (cost v_pre : ℤ) - (freqOf y v : ℤ) := by
                  have h := cost_mergePair_of_areSiblings v_pre y x y (freqOf y v_pre) 0
                    (fz := freqOf y v_pre + freqOf x v_pre)
                    h_sib_pre h_cons_pre (Ne.symm hx_ne_y) (by rw [h_fy_pre]) h_fx_pre
                    (by rw [h_fy_pre, h_fx_pre, add_zero])
                  simpa [v_pruned, h_fy_pre, h_fx_pre, add_zero] using h
                have h_fy_pos_int : (0 : ℤ) < freqOf y v := by exact_mod_cast h_freq_y_pos
                have h_cost_pre_le_v : (cost v_pre : ℤ) ≤ (cost v : ℤ) := h_cost_pre
                omega
              have h_cons_pruned : consistent v_pruned :=
                consistent_mergePair_same_sibling v_pre x y (freqOf y v_pre + freqOf x v_pre)
                  h_sib_pre h_cons_pre (Ne.symm hx_ne_y)
              have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                intro s
                have h_freq_pruned : freqOf s v_pruned = freqOf s v_pre := by
                  dsimp [v_pruned]
                  rw [freqOf_mergePair_same_sibling v_pre x y s h_sib_pre h_cons_pre (Ne.symm hx_ne_y),
                    h_fy_pre, h_fx_pre, add_zero]
                  by_cases hsy : s = y
                  · rw [hsy, if_pos rfl, h_fy_pre]
                  · by_cases hsx : s = x
                    · rw [hsx]
                      by_cases hxy' : x = y; · exfalso; exact hx_ne_y hxy'
                      rw [if_neg hxy', if_pos rfl, h_fx_pre]
                    · rw [if_neg hsy, if_neg hsx]
                rw [h_freq_pruned]
                dsimp [v_pre]
                rw [freqOf_exchangeLeaf v x y s hx_ne_y hx_in hy_in h_cons_v]
                exact h_sameFreqs_v s
              have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
              have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
              omega
            · -- Both x and y have zero frequency (degenerate case). Cost doesn't decrease on pruning.
              have h_freq_y_v : freqOf y v = 0 := by omega
              let v_pruned := mergePair x y x (freqOf x v + freqOf y v) v
              have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                have h_ne : x ≠ y := hx_ne_y
                have h_lt : nodeCount v_pruned < nodeCount v :=
                  nodeCount_mergePair_lt_of_areSiblings v x y x (freqOf x v + freqOf y v) h_dsp_sib_xy h_ne
                omega
              have h_cons_pruned : consistent v_pruned :=
                consistent_mergePair_same_sibling v y x (freqOf x v + freqOf y v) h_dsp_sib_xy h_cons_v hx_ne_y
              have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                intro s
                have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
                  dsimp [v_pruned]
                  rw [freqOf_mergePair_same_sibling v y x s h_dsp_sib_xy h_cons_v hx_ne_y]
                  by_cases hsx : s = x
                  · subst s; simp [hx_ne_y, h_freq_x_v, h_freq_y_v]
                  · by_cases hsy : s = y
                    · subst s; simp [hx_ne_y, h_freq_x_v, h_freq_y_v]
                    · simp [hsx, hsy, h_freq_x_v, h_freq_y_v]
                rw [h_freq_pruned, h_sameFreqs_v s]
              have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
              have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
              have h_cost_pruned_eq : cost v_pruned = cost v := by
                have h := cost_mergePair_of_areSiblings v x y x (freqOf x v) (freqOf y v)
                  (fz := freqOf x v + freqOf y v)
                  h_dsp_sib_xy h_cons_v hx_ne_y (by rfl) (by rfl) (by ring)
                simpa [v_pruned, h_freq_x_v, h_freq_y_v, add_zero] using h
              omega

  have h_all : ∀ n, P n := by
    intro n; exact Nat.strong_induction_on n hP
  exact h_all (nodeCount u) u rfl h_cons_u h_sameFreqs

theorem optimum_huffman (ts : List HuffTree)
    (h_sorted : forest_sorted ts)
    (h_cons : forest_consistent ts)
    (h_all_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_nonempty : ts ≠ []) :
    optimum (huffman ts) := by
  generalize hlen : ts.length = n
  induction n using Nat.strong_induction_on generalizing ts with
  | h n ih =>
    cases ts with
    | nil => exfalso; exact h_nonempty rfl
    | cons ta ts' =>
      cases ts' with
      | nil =>
        have h_leaf : height ta = 0 := h_all_leaves ta (by simp)
        have h_rf_pos : rootFreq ta > 0 := h_pos ta (by simp)
        cases ta with
        | htInner _ _ =>
          exfalso
          simp [height] at h_leaf
        | htLeaf s f =>
          simp [huffman]
          have h_f_pos : f > 0 := by simpa [rootFreq] using h_rf_pos
          exact optimum_leaf s f h_f_pos
      | cons tb ts'' =>
        have h1 : height ta = 0 := h_all_leaves ta (by simp)
        have h2 : height tb = 0 := h_all_leaves tb (by simp)
        have hp1 : rootFreq ta > 0 := h_pos ta (by simp)
        have hp2 : rootFreq tb > 0 := h_pos tb (by simp)
        cases ta with
        | htInner _ _ =>
          exfalso
          simp [height] at h1
        | htLeaf sa fa =>
          cases tb with
          | htInner _ _ =>
            exfalso
            simp [height] at h2
          | htLeaf sb fb =>
            have h_ne : sa ≠ sb := by
              intro h_eq; subst h_eq
              simp [forest_consistent] at h_cons
              rcases h_cons with ⟨_, _, hd⟩
              have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd.1
              have : sa ∈ alphabet (htLeaf sa fa) ∩ alphabet (htLeaf sa fb) :=
                Finset.mem_inter.mpr ⟨by simp [alphabet], by simp [alphabet]⟩
              rw [h_disjoint] at this
              simp at this
            have h_fa_pos : fa > 0 := by simpa [rootFreq] using hp1
            have h_fb_pos : fb > 0 := by simpa [rootFreq] using hp2
            cases ts'' with
            | nil =>
              simpa [huffman, insortTree, unite] using
                optimum_two_distinct_leaves sa fa sb fb h_ne h_fa_pos h_fb_pos
            | cons tc rest =>
              let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)
              have h_reduced_nonempty : reduced ≠ [] := by
                rw [← List.length_pos_iff_ne_nil, insortTree_length]
                omega
              have h_reduced_sorted : forest_sorted reduced := by
                apply forest_sorted_insortTree_of_sorted
                exact forest_sorted_tail (htLeaf sb fb) (tc :: rest)
                  (forest_sorted_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_sorted)
              have h_a_notin_rest : ∀ t ∈ tc :: rest, sa ∉ alphabet t := by
                intro t ht
                have h_disj : Disjoint (alphabet (htLeaf sa fa)) (alphabet t) := by
                  rw [forest_consistent_cons_iff] at h_cons
                  exact h_cons.2.2 t (by simp [ht])
                intro h_mem
                have : sa ∈ alphabet (htLeaf sa fa) ∩ alphabet t :=
                  Finset.mem_inter.mpr ⟨by simp [alphabet], h_mem⟩
                rw [Finset.disjoint_iff_inter_eq_empty.mp h_disj] at this
                simp at this
              have h_reduced_cons : forest_consistent reduced := by
                apply forest_consistent_insortTree_fresh sa (fa + fb) (tc :: rest)
                · exact h_a_notin_rest
                · exact forest_consistent_tail (htLeaf sb fb) (tc :: rest)
                    (forest_consistent_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_cons)
              have h_reduced_leaves : ∀ t ∈ reduced, height t = 0 := by
                intro t ht
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [height]
                · exact h_all_leaves t (by simp [ht])
              have h_reduced_pos : ∀ t ∈ reduced, rootFreq t > 0 := by
                intro t ht
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [rootFreq]; omega
                · exact h_pos t (by simp [ht])
              have h_len : reduced.length < n := by
                rw [← hlen]
                simp [reduced, insortTree_length]
              have h_opt_reduced : optimum (huffman reduced) :=
                ih reduced.length h_len reduced h_reduced_sorted h_reduced_cons
                  h_reduced_leaves h_reduced_pos h_reduced_nonempty rfl
              have h_cons_reduced : consistent (huffman reduced) :=
                consistent_huffman_of_consistent reduced h_reduced_nonempty h_reduced_cons
              have h_a_in_reduced : sa ∈ alphabet (huffman reduced) := by
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty]
                rw [mem_forest_alphabet]
                use htLeaf sa (fa + fb)
                constructor
                · rw [mem_insortTree]; simp
                · simp [alphabet]
              have h_b_notin_reduced : sb ∉ alphabet (huffman reduced) := by
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty]
                rw [mem_forest_alphabet]
                rintro ⟨t, ht, h_mem⟩
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [alphabet] at h_mem
                  have : sa = sb := h_mem.symm
                  contradiction
                · have h_mem_sb : sb ∈ alphabet t := by simpa using h_mem
                  have h_disj : Disjoint (alphabet (htLeaf sb fb)) (alphabet t) := by
                    rw [forest_consistent_cons_iff] at h_cons
                    exact h_cons.2.1.2.2 t (by simp [ht])
                  have : sb ∈ alphabet (htLeaf sb fb) ∩ alphabet t :=
                    Finset.mem_inter.mpr ⟨by simp [alphabet], h_mem_sb⟩
                  rw [Finset.disjoint_iff_inter_eq_empty.mp h_disj] at this
                  simp at this
              have h_freq_a : freqOf sa (huffman reduced) = fa + fb := by
                rw [freqOf_huffman_eq_forest_freq reduced sa h_reduced_nonempty]
                rw [forest_freq_insortTree]
                have h_zero : forest_freq (tc :: rest) sa = 0 := by
                  apply forest_freq_eq_zero_of_not_mem
                  rw [mem_forest_alphabet]
                  rintro ⟨t, ht, h_mem⟩
                  exact h_a_notin_rest t ht h_mem
                simp [forest_freq, freqOf] at h_zero ⊢
                omega
              have h_min : ∀ s ∈ alphabet (huffman reduced),
                  fa ≤ freqOf s (huffman reduced) ∧ fb ≤ freqOf s (huffman reduced) := by
                intro s hs
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty] at hs
                rw [mem_forest_alphabet] at hs
                rcases hs with ⟨t, ht, h_mem⟩
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · -- the combined leaf
                  have hs_eq : s = sa := by simpa [alphabet] using h_mem
                  rw [hs_eq]
                  rw [h_freq_a]
                  constructor <;> omega
                · -- a leaf from the original tail
                  have h_leaf_t : height t = 0 := h_all_leaves t (by simp [ht])
                  have h_s_ne_a : s ≠ sa := by
                    intro h_eq
                    rw [h_eq] at h_mem
                    exact h_a_notin_rest t ht h_mem
                  have h_freq_leaf : freqOf s (htLeaf sa (fa + fb)) = 0 := by
                    apply freqOf_eq_zero_of_not_mem
                    simp [alphabet, h_s_ne_a]
                  have h_freq_s : freqOf s (huffman reduced) = rootFreq t := by
                    rw [freqOf_huffman_eq_forest_freq reduced s h_reduced_nonempty]
                    rw [forest_freq_insortTree]
                    simp [forest_freq, h_freq_leaf]
                    exact forest_freq_eq_rootFreq_of_mem_leaf (tc :: rest) s t
                      (fun u hu => h_all_leaves u (by simp [hu]))
                      (forest_consistent_tail (htLeaf sb fb) (tc :: rest)
                        (forest_consistent_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_cons))
                      ht h_mem
                  rw [h_freq_s]
                  constructor
                  · have h_le := rootFreq_le_of_mem_sorted (htLeaf sa fa) (htLeaf sb fb :: tc :: rest)
                      h_sorted t (by simp [ht])
                    simp [rootFreq] at h_le ⊢
                    omega
                  · have h_le := rootFreq_le_of_mem_sorted (htLeaf sb fb) (tc :: rest)
                      (forest_sorted_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_sorted) t
                      (by simp [ht])
                    simp [rootFreq] at h_le ⊢
                    omega
              have h_opt_split : optimum (splitLeaf (huffman reduced) sa sa sb fa fb) := by
                apply optimum_splitLeaf (huffman reduced) sa sb fa fb
                  h_opt_reduced h_a_in_reduced h_b_notin_reduced h_ne
                  h_fa_pos h_fb_pos _ _ _ h_freq_a
                · -- fa ≤ fb
                  have h_le : rootFreq (htLeaf sa fa) ≤ rootFreq (htLeaf sb fb) := by
                    simp [forest_sorted] at h_sorted
                    exact h_sorted.1
                  simp [rootFreq] at h_le ⊢
                  omega
                · -- fa minimum
                  intro s hs
                  exact (h_min s hs).1
                · -- fb minimum for s ≠ sa
                  intro s hs h_s_ne_a
                  exact (h_min s hs).2
              have h_eq : splitLeaf (huffman reduced) sa sa sb fa fb =
                  huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest) := by
                have h_a_notin_tc_rest : ∀ t ∈ tc :: rest, sa ∉ alphabet t := h_a_notin_rest
                rw [show reduced = insortTree (htLeaf sa (fa + fb)) (tc :: rest) by rfl]
                rw [splitLeaf_huffman_commute sa sb fa fb (tc :: rest) h_a_notin_tc_rest]
                simp [huffman, insortTree, unite]
              rw [h_eq] at h_opt_split
              exact h_opt_split
