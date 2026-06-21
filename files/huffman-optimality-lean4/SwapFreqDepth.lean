import CfProofs.Greedy.Huffman.Base
open HuffTree

lemma freqOf_swapLeaves_of_not_is (a b s : ℕ) (t : HuffTree) (h_ne_a : s ≠ a) (h_ne_b : s ≠ b) :
    freqOf s (swapLeaves a b t) = freqOf s t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm]
        · simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm, hba]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma freqOf_swapLeaves_at_a (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    freqOf a (swapLeaves a b t) = freqOf b t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne.symm]
        · simp [swapLeaves, freqOf, h_ne.symm, hba]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma freqOf_swapLeaves_at_b (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    freqOf b (swapLeaves a b t) = freqOf a t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne]
        · simp [swapLeaves, freqOf, hba, h_ne, h_ne.symm]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma depthOf_swapLeaves_of_not_is (a b s : ℕ) (t : HuffTree) (h_ne_a : s ≠ a) (h_ne_b : s ≠ b) :
    depthOf s (swapLeaves a b t) = depthOf s t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm]
        · simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm, hba]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_swapLeaves_at_a (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    depthOf a (swapLeaves a b t) = depthOf b t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne.symm]
        · simp [swapLeaves, depthOf, h_ne.symm, hba]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_swapLeaves_at_b (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    depthOf b (swapLeaves a b t) = depthOf a t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne]
        · simp [swapLeaves, depthOf, hba, h_ne, h_ne.symm]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_replaceFreq_eq (sym newFreq s : ℕ) (t : HuffTree) :
    depthOf s (replaceFreq sym newFreq t) = depthOf s t := by
  induction t with
  | htLeaf sym' f =>
    by_cases h : sym' = sym
    · subst h; simp [replaceFreq, depthOf]
    · simp [replaceFreq, depthOf, h]
  | htInner l r ihl ihr => simp [replaceFreq, depthOf, ihl, ihr]

lemma depthOf_swapFreqs_eq (a c s : ℕ) (t : HuffTree) :
    depthOf s (swapFreqs a c t) = depthOf s t := by
  rw [swapFreqs, depthOf_replaceFreq_eq, depthOf_replaceFreq_eq]
