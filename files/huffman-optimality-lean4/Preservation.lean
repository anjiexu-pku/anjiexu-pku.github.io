import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.Commutation

open HuffTree

/-! # Huffman preserves forest frequencies and alphabet

For a non-empty forest `ts`, the tree `huffman ts` encodes exactly the same
symbols with the same frequencies as the whole forest, and it is consistent
whenever the forest is consistent.
-/

def forest_freq (ts : List HuffTree) (s : ℕ) : ℕ := (ts.map (freqOf s)).sum

def forest_alphabet : List HuffTree → Finset ℕ
  | [] => ∅
  | t :: ts => alphabet t ∪ forest_alphabet ts

lemma mem_forest_alphabet (ts : List HuffTree) (s : ℕ) :
    s ∈ forest_alphabet ts ↔ ∃ t ∈ ts, s ∈ alphabet t := by
  induction ts with
  | nil => simp [forest_alphabet]
  | cons t ts ih =>
    simp [forest_alphabet, ih]

lemma forest_freq_cons (t : HuffTree) (ts : List HuffTree) (s : ℕ) :
    forest_freq (t :: ts) s = freqOf s t + forest_freq ts s := by
  simp [forest_freq]

lemma forest_alphabet_cons (t : HuffTree) (ts : List HuffTree) :
    forest_alphabet (t :: ts) = alphabet t ∪ forest_alphabet ts := by
  simp [forest_alphabet]

lemma forest_freq_insortTree (t : HuffTree) (ts : List HuffTree) (s : ℕ) :
    forest_freq (insortTree t ts) s = forest_freq (t :: ts) s := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_freq]
  | cons u us ih =>
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_freq]
    · simp [h, forest_freq]
      have h_ih := ih t
      simp [forest_freq] at h_ih ⊢
      omega

lemma forest_alphabet_insortTree (t : HuffTree) (ts : List HuffTree) :
    forest_alphabet (insortTree t ts) = forest_alphabet (t :: ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_alphabet]
  | cons u us ih =>
    simp [insortTree, forest_alphabet]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_alphabet]
    · simp [h, ih, forest_alphabet]
      ac_rfl

lemma freqOf_huffman_eq_forest_freq (ts : List HuffTree) (s : ℕ) (h_nonempty : ts ≠ []) :
    freqOf s (huffman ts) = forest_freq ts s := by
  induction ts using huffman.induct with
  | case1 => exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman, forest_freq]
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman, forest_freq_insortTree, IH h_rec]
    simp [forest_freq]
    have h_unite : freqOf s (unite t1 t2) = freqOf s t1 + freqOf s t2 := by
      simp [unite, freqOf]
    rw [h_unite]
    omega

lemma alphabet_huffman_eq_forest_alphabet (ts : List HuffTree) (h_nonempty : ts ≠ []) :
    alphabet (huffman ts) = forest_alphabet ts := by
  induction ts using huffman.induct with
  | case1 => exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman, forest_alphabet]
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman, forest_alphabet_insortTree, IH h_rec]
    simp [forest_alphabet]
    have h_unite : alphabet (unite t1 t2) = alphabet t1 ∪ alphabet t2 := by
      simp [unite, alphabet]
    rw [h_unite]
    ac_rfl

lemma forest_sorted_insortTree_head (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) : forest_sorted (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_sorted]
  | cons u us ih =>
    have htu : rootFreq t ≤ rootFreq u := by
      simp [forest_sorted] at h_sorted
      exact h_sorted.1
    simp [insortTree, htu]
    simpa [forest_sorted] using h_sorted

lemma forest_consistent_cons_iff (t : HuffTree) (ts : List HuffTree) :
    forest_consistent (t :: ts) ↔
      consistent t ∧ forest_consistent ts ∧ ∀ u ∈ ts, Disjoint (alphabet t) (alphabet u) := by
  cases ts with
  | nil => simp [forest_consistent]
  | cons u us => simp [forest_consistent]

lemma forest_consistent_tail (t : HuffTree) (ts : List HuffTree)
    (h_cons : forest_consistent (t :: ts)) : forest_consistent ts := by
  rw [forest_consistent_cons_iff] at h_cons
  exact h_cons.2.1

lemma forall_mem_tail {α : Type*} {P : α → Prop} (t : α) (ts : List α)
    (h : ∀ x ∈ t :: ts, P x) : ∀ x ∈ ts, P x := by
  intro x hx
  exact h x (by simp [hx])

lemma forest_consistent_insortTree_fresh (z fz : ℕ) (ts : List HuffTree)
    (h_fresh : ∀ t ∈ ts, z ∉ alphabet t)
    (h_cons : forest_consistent ts) :
    forest_consistent (insortTree (htLeaf z fz) ts) := by
  induction ts with
  | nil =>
    simp [insortTree, forest_consistent]
    simp [consistent]
  | cons u us ih =>
    have h_fresh_u : z ∉ alphabet u := h_fresh u (by simp)
    have h_fresh_us : ∀ t ∈ us, z ∉ alphabet t := forall_mem_tail u us h_fresh
    have h_cons_us : forest_consistent us := forest_consistent_tail u us h_cons
    rw [forest_consistent_cons_iff] at h_cons
    have hcu : consistent u := h_cons.1
    have hdisj_u : ∀ w ∈ us, Disjoint (alphabet u) (alphabet w) := h_cons.2.2
    simp [insortTree]
    split_ifs with h
    · -- fresh leaf becomes the head: htLeaf z fz :: u :: us
      rw [forest_consistent_cons_iff]
      refine ⟨by simp [consistent], ?_, ?_⟩
      · rw [forest_consistent_cons_iff]
        refine ⟨hcu, h_cons_us, hdisj_u⟩
      · intro w hw
        simp [alphabet] at hw ⊢
        cases hw with
        | inl h_eq =>
          rw [h_eq]
          exact h_fresh_u
        | inr h_mem =>
          exact h_fresh_us w h_mem
    · -- recurse: u :: insortTree (htLeaf z fz) us
      rw [forest_consistent_cons_iff]
      have h_cons_insort : forest_consistent (insortTree (htLeaf z fz) us) :=
        ih h_fresh_us h_cons_us
      have hdisj_u_insort : ∀ w ∈ insortTree (htLeaf z fz) us, Disjoint (alphabet u) (alphabet w) := by
        intro w hw
        rw [mem_insortTree] at hw
        cases hw with
        | inl h_eq =>
          rw [h_eq]
          simp [alphabet]
          exact h_fresh_u
        | inr h_mem =>
          exact hdisj_u w h_mem
      refine ⟨hcu, h_cons_insort, hdisj_u_insort⟩

lemma forest_freq_pos_of_all_leaves_pos (ts : List HuffTree) (s : ℕ)
    (h_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_mem : s ∈ forest_alphabet ts) :
    forest_freq ts s > 0 := by
  rw [mem_forest_alphabet] at h_mem
  rcases h_mem with ⟨t, ht, hs⟩
  have h_leaf : height t = 0 := h_leaves t ht
  rcases height_eq_zero_iff t |>.mp h_leaf with ⟨sym, f, ht_eq⟩
  rw [ht_eq] at ht hs
  simp [alphabet] at hs
  subst hs
  have hf_pos : f > 0 := by
    simpa [rootFreq] using h_pos (htLeaf s f) ht
  have h_freq_pos : freqOf s (htLeaf s f) > 0 := by simp [freqOf]; exact hf_pos
  have h_sum_pos : forest_freq ts s > 0 := by
    simp [forest_freq]
    have h1 : freqOf s (htLeaf s f) ∈ ts.map (freqOf s) := by
      apply List.mem_map_of_mem
      exact ht
    have h2 : freqOf s (htLeaf s f) ≤ (ts.map (freqOf s)).sum := by
      apply List.single_le_sum
      · intro x _; exact Nat.zero_le x
      · exact h1
    omega
  exact h_sum_pos

lemma forest_freq_eq_zero_of_not_mem (ts : List HuffTree) (s : ℕ)
    (h : s ∉ forest_alphabet ts) : forest_freq ts s = 0 := by
  simp [forest_freq]
  apply List.sum_eq_zero
  intro x hx
  rcases List.mem_map.mp hx with ⟨t, ht, rfl⟩
  have h_not_mem : s ∉ alphabet t := by
    by_contra h_mem
    have : s ∈ forest_alphabet ts := by
      rw [mem_forest_alphabet]
      refine ⟨t, ht, h_mem⟩
    contradiction
  have h_zero : freqOf s t = 0 := freqOf_eq_zero_of_not_mem s t h_not_mem
  simp [h_zero]

lemma forest_freq_eq_rootFreq_of_mem_leaf (ts : List HuffTree) (s : ℕ) (t : HuffTree)
    (h_leaves : ∀ u ∈ ts, height u = 0)
    (h_cons : forest_consistent ts)
    (ht : t ∈ ts)
    (hs : s ∈ alphabet t) :
    forest_freq ts s = rootFreq t := by
  induction ts generalizing t with
  | nil => simp at ht
  | cons u us ih =>
    by_cases h_eq : t = u
    · -- t is the head
      subst h_eq
      simp [forest_freq]
      have h_zero : forest_freq us s = 0 := by
        apply forest_freq_eq_zero_of_not_mem
        rw [mem_forest_alphabet]
        intro h
        rcases h with ⟨v, hv, h_mem⟩
        have h_disjoint : Disjoint (alphabet t) (alphabet v) := by
          rw [forest_consistent_cons_iff] at h_cons
          exact h_cons.2.2 v hv
        have h_s_in_tv : s ∈ alphabet t ∩ alphabet v := by
          simp [hs, h_mem]
        rw [Finset.disjoint_iff_inter_eq_empty.mp h_disjoint] at h_s_in_tv
        simp at h_s_in_tv
      have h_freq_t : freqOf s t = rootFreq t := by
        have h_leaf_t : height t = 0 := h_leaves t (by simp)
        rcases height_eq_zero_iff t |>.mp h_leaf_t with ⟨sym, f, ht_eq⟩
        rw [ht_eq] at hs
        simp [alphabet] at hs
        subst hs
        rw [ht_eq]
        simp [freqOf, rootFreq]
      simp [h_freq_t, forest_freq] at h_zero ⊢
      omega
    · -- t is in the tail
      have h_mem' : t ∈ us := by
        simp [h_eq] at ht
        exact ht
      simp [forest_freq]
      have h_zero : freqOf s u = 0 := by
        have h_not_mem : s ∉ alphabet u := by
          rw [forest_consistent_cons_iff] at h_cons
          have h_disjoint : Disjoint (alphabet u) (alphabet t) := h_cons.2.2 t h_mem'
          intro h_su
          have h_s_in_ut : s ∈ alphabet u ∩ alphabet t := by
            simp [h_su, hs]
          rw [Finset.disjoint_iff_inter_eq_empty.mp h_disjoint] at h_s_in_ut
          simp at h_s_in_ut
        exact freqOf_eq_zero_of_not_mem s u h_not_mem
      have h_rec : forest_freq us s = rootFreq t := by
        apply ih
        · intro v hv
          exact h_leaves v (by simp [hv])
        · rw [forest_consistent_cons_iff] at h_cons
          exact h_cons.2.1
        · exact h_mem'
        · exact hs
      simp [forest_freq] at h_rec ⊢
      simp [h_zero, h_rec]


-- Sortedness lemmas for insertion into a forest

lemma forest_sorted_tail (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) : forest_sorted ts := by
  cases ts with
  | nil => simp [forest_sorted]
  | cons u us => simpa [forest_sorted] using h_sorted.2

lemma forest_sorted_insortTree_of_sorted (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted ts) : forest_sorted (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_sorted]
  | cons u us ih =>
    have h_sorted_us : forest_sorted us := forest_sorted_tail u us h_sorted
    have ih' := ih t h_sorted_us
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_sorted, h_sorted]
    · simp [h]
      have h_ne : insortTree t us ≠ [] := by
        rw [← List.length_pos_iff_ne_nil, insortTree_length]
        omega
      have h1 : rootFreq u ≤ rootFreq ((insortTree t us).head h_ne) := by
        cases us with
        | nil =>
          simp [insortTree]
          omega
        | cons v vs =>
          simp [insortTree]
          by_cases h2 : rootFreq t ≤ rootFreq v
          · simp [h2]; omega
          · simp [h2]; simp [forest_sorted] at h_sorted; omega
      have ih' := ih t h_sorted_us
      cases h_r : insortTree t us with
      | nil =>
        exfalso
        exact h_ne h_r
      | cons x xs =>
        simp [h_r] at h1 ih'
        simp [forest_sorted]
        constructor
        · exact h1
        · exact ih'

-- Consistency is preserved by insertion and by Huffman merging

lemma forest_consistent_insortTree (t : HuffTree) (ts : List HuffTree)
    (h_cons : forest_consistent (t :: ts)) :
    forest_consistent (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simpa [insortTree]
  | cons u us ih =>
    have h_cons_u_us : forest_consistent (u :: us) := by
      rw [forest_consistent_cons_iff] at h_cons
      exact h_cons.2.1
    have h_cons_us : forest_consistent us :=
      forest_consistent_tail u us h_cons_u_us
    have h_cons_t_us : forest_consistent (t :: us) := by
      rw [forest_consistent_cons_iff]
      refine ⟨?_, h_cons_us, ?_⟩
      · rw [forest_consistent_cons_iff] at h_cons
        exact h_cons.1
      · intro w hw
        rw [forest_consistent_cons_iff] at h_cons
        exact h_cons.2.2 w (by simp [hw])
    have ih' := ih t h_cons_t_us
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · -- insortTree places t at the head: t :: u :: us
      simp [h]
      exact h_cons
    · -- insortTree keeps u at the head
      simp [h]
      rw [forest_consistent_cons_iff]
      refine ⟨?_, ih', ?_⟩
      · rw [forest_consistent_cons_iff] at h_cons_u_us
        exact h_cons_u_us.1
      · intro w hw
        rw [mem_insortTree] at hw
        rcases hw with rfl | hw
        · -- w = t
          rw [forest_consistent_cons_iff] at h_cons
          have hdisj : Disjoint (alphabet w) (alphabet u) :=
            h_cons.2.2 u (by simp)
          exact Disjoint.symm hdisj
        · -- w ∈ us
          rw [forest_consistent_cons_iff] at h_cons_u_us
          exact h_cons_u_us.2.2 w hw

lemma consistent_unite (t1 t2 : HuffTree)
    (h1 : consistent t1) (h2 : consistent t2)
    (hdisj : Disjoint (alphabet t1) (alphabet t2)) :
    consistent (unite t1 t2) := by
  simp [unite, consistent, h1, h2, hdisj]

lemma forest_consistent_unite_head (t1 t2 : HuffTree) (rest : List HuffTree)
    (h_cons : forest_consistent (t1 :: t2 :: rest)) :
    forest_consistent (unite t1 t2 :: rest) := by
  cases rest with
  | nil =>
    simp [forest_consistent]
    have h1 : consistent t1 := h_cons.1
    have h2 : consistent t2 := h_cons.2.1
    have h12 : Disjoint (alphabet t1) (alphabet t2) := h_cons.2.2 t2 (by simp)
    exact consistent_unite t1 t2 h1 h2 h12
  | cons r rs =>
    rw [forest_consistent_cons_iff] at h_cons
    rw [forest_consistent_cons_iff]
    have h1 : consistent t1 := h_cons.1
    have h2 : consistent t2 := h_cons.2.1.1
    have hrs : forest_consistent (r :: rs) := h_cons.2.1.2.1
    have h2r : ∀ w ∈ r :: rs, Disjoint (alphabet t2) (alphabet w) := h_cons.2.1.2.2
    have h12 : Disjoint (alphabet t1) (alphabet t2) := h_cons.2.2 t2 (by simp)
    have h1rs : ∀ w ∈ r :: rs, Disjoint (alphabet t1) (alphabet w) := by
      intro w hw
      exact h_cons.2.2 w (by simp [hw])
    refine ⟨consistent_unite t1 t2 h1 h2 h12, hrs, ?_⟩
    intro w hw
    simp [unite, alphabet]
    constructor
    · exact h1rs w hw
    · exact h2r w hw

lemma consistent_huffman_of_consistent (ts : List HuffTree)
    (h_nonempty : ts ≠ []) (h_cons : forest_consistent ts) :
    consistent (huffman ts) := by
  induction ts using huffman.induct with
  | case1 =>
    exfalso; exact h_nonempty rfl
  | case2 t =>
    simp [huffman]
    simp [forest_consistent] at h_cons
    exact h_cons
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman]
    apply IH h_rec
    apply forest_consistent_insortTree
    apply forest_consistent_unite_head
    exact h_cons

-- Positivity of frequencies in a Huffman tree

lemma freqOf_huffman_pos_of_mem (ts : List HuffTree) (s : ℕ)
    (h_nonempty : ts ≠ [])
    (h_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_cons : forest_consistent ts)
    (h_mem : s ∈ alphabet (huffman ts)) :
    freqOf s (huffman ts) > 0 := by
  rw [freqOf_huffman_eq_forest_freq ts s h_nonempty]
  rw [alphabet_huffman_eq_forest_alphabet ts h_nonempty] at h_mem
  exact forest_freq_pos_of_all_leaves_pos ts s h_leaves h_pos h_mem

-- Sortedness implies the head frequency is a lower bound for the tail

lemma rootFreq_le_of_mem_sorted (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) :
    ∀ u ∈ ts, rootFreq t ≤ rootFreq u := by
  induction ts generalizing t with
  | nil => simp
  | cons v vs ih =>
    intro u hu
    simp [forest_sorted] at h_sorted
    by_cases huv : u = v
    · rw [huv]; exact h_sorted.1
    · have hu' : u ∈ vs := by
        simp [huv] at hu
        exact hu
      have htv : rootFreq t ≤ rootFreq v := h_sorted.1
      have h_sorted_t_vs : forest_sorted (t :: vs) := by
        cases vs with
        | nil => simp [forest_sorted]
        | cons w ws =>
          simp [forest_sorted]
          constructor
          · -- rootFreq t ≤ rootFreq w
            have hvw : rootFreq v ≤ rootFreq w := by
              apply ih v h_sorted.2 w (by simp)
            omega
          · exact h_sorted.2.2
      have htw : rootFreq t ≤ rootFreq u := ih t h_sorted_t_vs u hu'
      exact htw
