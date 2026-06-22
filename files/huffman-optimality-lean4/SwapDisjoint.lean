import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.SwapBasic
import CfProofs.Greedy.Huffman.SwapFreqDepth
open HuffTree

def swapSym (a b s : ℕ) : ℕ := if s = a then b else if s = b then a else s

lemma swapSym_involutive (a b : ℕ) : Function.Involutive (swapSym a b) := by
  intro s
  dsimp [swapSym]
  by_cases hsa : s = a
  · subst s; simp
  · by_cases hsb : s = b
    · subst s
      by_cases hba : b = a
      · subst b; simp
      · have h1 : swapSym a b b = a := by dsimp [swapSym]; simp [hba]
        have h2 : swapSym a b a = b := by dsimp [swapSym]; simp
        calc
          swapSym a b (swapSym a b b) = swapSym a b a := by rw [h1]
          _ = b := h2
    · simp [hsa, hsb]

lemma swapSym_injective (a b : ℕ) : Function.Injective (swapSym a b) :=
  (swapSym_involutive a b).injective

lemma alphabet_swapLeaves_eq_image (a b : ℕ) (t : HuffTree) :
    alphabet (swapLeaves a b t) = (alphabet t).image (swapSym a b) := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · subst s; simp [swapLeaves, alphabet, swapSym]
    · by_cases hsb : s = b
      · subst s; simp [swapLeaves, alphabet, swapSym, hsa]
      · simp [swapLeaves, alphabet, swapSym, hsa, hsb]
  | htInner l r ihl ihr =>
    simp [swapLeaves, alphabet, ihl, ihr, Finset.image_union]

lemma swapLeaves_preserves_disjoint (a b : ℕ) (l r : HuffTree)
    (hd : Disjoint (alphabet l) (alphabet r)) :
    Disjoint (alphabet (swapLeaves a b l)) (alphabet (swapLeaves a b r)) := by
  rw [alphabet_swapLeaves_eq_image a b l, alphabet_swapLeaves_eq_image a b r]
  exact (Finset.disjoint_image (swapSym_injective a b)).mpr hd

lemma consistent_swapLeaves (a b : ℕ) (t : HuffTree) (h_cons : consistent t) :
    consistent (swapLeaves a b t) := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, consistent]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, consistent]
        · simp [swapLeaves, consistent, hba]
      · simp [swapLeaves, consistent, hsa, hsb]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    rw [swapLeaves, consistent]
    have h_l := ihl hcl; have h_r := ihr hcr
    have hd' : Disjoint (alphabet (swapLeaves a b l)) (alphabet (swapLeaves a b r)) :=
      swapLeaves_preserves_disjoint a b l r hd
    exact ⟨h_l, h_r, hd'⟩

lemma freqOf_replaceFreq_eq_of_mem (sym f : ℕ) (t : HuffTree) (h_sym : sym ∈ alphabet t) (h_cons : consistent t) :
    freqOf sym (replaceFreq sym f t) = f := by
  induction t with
  | htLeaf s g =>
    simp [alphabet] at h_sym; subst h_sym; simp [replaceFreq, freqOf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [replaceFreq, freqOf]
    simp [alphabet] at h_sym
    rcases h_sym with (hl | hr)
    · have hr_not : sym ∉ alphabet r := by
        intro hm; have hi := Finset.mem_inter.mpr ⟨hl, hm⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      have h_r : freqOf sym (replaceFreq sym f r) = 0 :=
        freqOf_eq_zero_of_not_mem sym (replaceFreq sym f r)
          (by rw [alphabet_replaceFreq sym f r]; exact hr_not)
      rw [ihl hl hcl, h_r, add_zero]
    · have hl_not : sym ∉ alphabet l := by
        intro hm; have hi := Finset.mem_inter.mpr ⟨hm, hr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      have h_l : freqOf sym (replaceFreq sym f l) = 0 :=
        freqOf_eq_zero_of_not_mem sym (replaceFreq sym f l)
          (by rw [alphabet_replaceFreq sym f l]; exact hl_not)
      rw [ihr hr hcr, h_l, zero_add]

lemma freqOf_exchangeLeaf (t : HuffTree) (a x s : ℕ) (h_ne : a ≠ x)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_cons : consistent t) :
    freqOf s (swapFreqs a x (swapLeaves a x t)) = freqOf s t := by
  have h_ne' : x ≠ a := Ne.symm h_ne
  let t' := swapLeaves a x t
  have h_cons_t' : consistent t' := consistent_swapLeaves a x t h_cons
  have ha_t' : freqOf a t' = freqOf x t := freqOf_swapLeaves_at_a a x t h_ne
  have hx_t' : freqOf x t' = freqOf a t := freqOf_swapLeaves_at_b a x t h_ne
  have ha_mem_t' : a ∈ alphabet t' := by
    rw [alphabet_swapLeaves_eq_image a x t, Finset.mem_image]
    exact ⟨x, hx_in, by dsimp [swapSym]; simp [h_ne']⟩
  have hx_mem_t' : x ∈ alphabet t' := by
    rw [alphabet_swapLeaves_eq_image a x t, Finset.mem_image]
    exact ⟨a, ha_in, by dsimp [swapSym]; simp⟩
  by_cases hs_a : s = a
  · rw [hs_a]
    dsimp [swapFreqs]
    rw [hx_t', ha_t']
    -- freqOf a (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
    rw [freqOf_replaceFreq_of_ne x (freqOf x t) a (replaceFreq a (freqOf a t) t') h_ne]
    rw [freqOf_replaceFreq_eq_of_mem a (freqOf a t) t' ha_mem_t' h_cons_t']
  · by_cases hs_x : s = x
    · rw [hs_x]
      dsimp [swapFreqs]
      rw [hx_t', ha_t']
      -- freqOf x (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
      have h_cons_t1 : consistent (replaceFreq a (freqOf a t) t') :=
        consistent_replaceFreq a (freqOf a t) t' h_cons_t'
      have hx_mem_t1 : x ∈ alphabet (replaceFreq a (freqOf a t) t') := by
        rw [alphabet_replaceFreq a (freqOf a t) t']; exact hx_mem_t'
      rw [freqOf_replaceFreq_eq_of_mem x (freqOf x t) (replaceFreq a (freqOf a t) t') hx_mem_t1 h_cons_t1]
    · -- s ≠ a and s ≠ x
      have hs_t' : freqOf s t' = freqOf s t :=
        freqOf_swapLeaves_of_not_is a x s t hs_a hs_x
      have hs_ne_a : s ≠ a := hs_a
      have hs_ne_x : s ≠ x := hs_x
      dsimp [swapFreqs]
      -- freqOf s (replaceFreq x (freqOf a t') (replaceFreq a (freqOf x t') t'))
      rw [hx_t', ha_t']
      -- freqOf s (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
      rw [freqOf_replaceFreq_of_ne x (freqOf x t) s (replaceFreq a (freqOf a t) t') hs_ne_x]
      rw [freqOf_replaceFreq_of_ne a (freqOf a t) s t' hs_ne_a, hs_t']

lemma cost_exchangeLeaf_le (t : HuffTree) (a x : ℕ) (h_cons : consistent t)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_ne : a ≠ x)
    (h_freq : freqOf a t ≤ freqOf x t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf x t).getD 0) :
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ) ≤ (cost t : ℤ) := by
  have h_ne' : x ≠ a := Ne.symm h_ne
  let t1 := swapLeaves a x t
  have h_cost_t1 : cost t1 = cost t := cost_swapLeaves_eq a x t
  have h_cons_t1 : consistent t1 := consistent_swapLeaves a x t h_cons
  have h_fa_t1 : freqOf a t1 = freqOf x t := freqOf_swapLeaves_at_a a x t h_ne
  have h_fx_t1 : freqOf x t1 = freqOf a t := freqOf_swapLeaves_at_b a x t h_ne
  have h_da_val : (depthOf a t1).getD 0 = (depthOf x t).getD 0 := by
    have h := depthOf_swapLeaves_at_a a x t h_ne; simp [t1, h]
  have h_dx_val : (depthOf x t1).getD 0 = (depthOf a t).getD 0 := by
    have h := depthOf_swapLeaves_at_b a x t h_ne; simp [t1, h]
  let t2 := replaceFreq a (freqOf x t1) t1
  have h_cons_t2 : consistent t2 := consistent_replaceFreq a (freqOf x t1) t1 h_cons_t1
  have h_fx_t2 : freqOf x t2 = freqOf x t1 := by
    simp [t2, freqOf_replaceFreq_of_ne a (freqOf x t1) x t1 h_ne']
  have h_dx_t2_val : (depthOf x t2).getD 0 = (depthOf x t1).getD 0 := by
    simp [t2, depthOf_replaceFreq_eq a (freqOf x t1) x t1]
  calc
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ)
        = (cost (swapFreqs a x t1) : ℤ) := by simp [t1]
    _ = (cost (replaceFreq x (freqOf a t1) t2) : ℤ) := by simp [t2, swapFreqs]
    _ = (cost t2 : ℤ) + (((freqOf a t1 : ℤ) - (freqOf x t2 : ℤ)) * ((depthOf x t2).getD 0 : ℤ)) :=
      cost_replaceFreq_eq x (freqOf a t1) t2 h_cons_t2
    _ = (cost t2 : ℤ) + (((freqOf x t : ℤ) - (freqOf a t : ℤ)) * ((depthOf a t).getD 0 : ℤ)) := by
      simp [h_fa_t1, h_fx_t2, h_fx_t1, h_dx_t2_val, h_dx_val]
    _ = ((cost t : ℤ) + (((freqOf a t : ℤ) - (freqOf x t : ℤ)) * ((depthOf x t).getD 0 : ℤ))) +
        (((freqOf x t : ℤ) - (freqOf a t : ℤ)) * ((depthOf a t).getD 0 : ℤ)) := by
      have h_t2_eq_raw := cost_replaceFreq_eq a (freqOf x t1) t1 h_cons_t1
      have h_t2_eq : (cost t2 : ℤ) = (cost t1 : ℤ) + (((freqOf x t1 : ℤ) - (freqOf a t1 : ℤ)) * ((depthOf a t1).getD 0 : ℤ)) := by
        simpa [t2] using h_t2_eq_raw
      rw [h_t2_eq]
      simp [h_cost_t1, h_fx_t1, h_fa_t1, h_da_val]
    _ = (cost t : ℤ) + (((freqOf a t : ℤ) - (freqOf x t : ℤ)) * (((depthOf x t).getD 0 : ℤ) - ((depthOf a t).getD 0 : ℤ))) := by ring
    _ ≤ (cost t : ℤ) := by
      have h_fa_le_fx_int : (freqOf a t : ℤ) ≤ (freqOf x t : ℤ) := by exact_mod_cast h_freq
      have h_da_le_dx_int : ((depthOf a t).getD 0 : ℤ) ≤ ((depthOf x t).getD 0 : ℤ) := by exact_mod_cast h_depth
      nlinarith
