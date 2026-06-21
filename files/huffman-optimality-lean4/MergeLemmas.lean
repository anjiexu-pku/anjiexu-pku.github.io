import CfProofs.Greedy.Huffman.Base
open HuffTree

inductive areSiblings (a b : ℕ) : HuffTree → Prop
  | here (fa fb : ℕ) : areSiblings a b (htInner (htLeaf a fa) (htLeaf b fb))
  | here' (fa fb : ℕ) : areSiblings a b (htInner (htLeaf b fb) (htLeaf a fa))
  | inLeft (l r : HuffTree) : areSiblings a b l → areSiblings a b (htInner l r)
  | inRight (l r : HuffTree) : areSiblings a b r → areSiblings a b (htInner l r)

lemma mergePair_eq_self_of_not_mem (a b z fz : ℕ) (t : HuffTree)
    (ha : a ∉ alphabet t) (hb : b ∉ alphabet t) : mergePair a b z fz t = t := by
  induction t with
  | htLeaf s f => simp [mergePair]
  | htInner l r ihl ihr =>
    have ha_l : a ∉ alphabet l := by intro hm; apply ha; simp [alphabet, hm]
    have hb_l : b ∉ alphabet l := by intro hm; apply hb; simp [alphabet, hm]
    have ha_r : a ∉ alphabet r := by intro hm; apply ha; simp [alphabet, hm]
    have hb_r : b ∉ alphabet r := by intro hm; apply hb; simp [alphabet, hm]
    have hl := ihl ha_l hb_l
    have hr := ihr ha_r hb_r
    cases l with
    | htLeaf sl fl =>
      cases r with
      | htLeaf sr fr =>
        have h_not_pair : ¬ ((sl = a ∧ sr = b) ∨ (sl = b ∧ sr = a)) := by
          intro h; rcases h with (⟨hsl, hsr⟩ | ⟨hsl, hsr⟩)
          · subst hsl hsr; exact ha (by simp [alphabet])
          · subst hsl hsr; exact ha (by simp [alphabet])
        simp [mergePair, h_not_pair, hl, hr]
      | htInner _ _ => simp [mergePair, hl, hr]
    | htInner _ _ => simp [mergePair, hl, hr]

lemma nodeCount_mergePair_le (a b z fz : ℕ) (t : HuffTree) :
    nodeCount (mergePair a b z fz t) ≤ nodeCount t := by
  induction t with
  | htLeaf s f => simp [mergePair, nodeCount]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy =>
        simp [mergePair, nodeCount]
        by_cases hc : (x = a ∧ y = b) ∨ (x = b ∧ y = a)
        · simp [hc, nodeCount]
        · simp [hc, nodeCount]
      | htInner rl rr =>
        have hm : mergePair a b z fz (htInner (htLeaf x fx) (htInner rl rr)) =
          htInner (htLeaf x fx) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihr ⊢
        omega
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have hm : mergePair a b z fz (htInner (htInner ll lr) (htLeaf y fy)) =
          htInner (mergePair a b z fz (htInner ll lr)) (htLeaf y fy) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihl ⊢
        omega
      | htInner rl rr =>
        have hm : mergePair a b z fz (htInner (htInner ll lr) (htInner rl rr)) =
          htInner (mergePair a b z fz (htInner ll lr)) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihl ihr ⊢
        omega

lemma areSiblings_mem_alphabet {a b : ℕ} {t : HuffTree} (h_sib : areSiblings a b t) :
    a ∈ alphabet t ∧ b ∈ alphabet t := by
  induction h_sib with
  | here fa fb => simp [alphabet]
  | here' fa fb => simp [alphabet]
  | inLeft l r h ih =>
    rcases ih with ⟨ha, hb⟩
    exact ⟨Finset.mem_union_left _ ha, Finset.mem_union_left _ hb⟩
  | inRight l r h ih =>
    rcases ih with ⟨ha, hb⟩
    exact ⟨Finset.mem_union_right _ ha, Finset.mem_union_right _ hb⟩

lemma nodeCount_mergePair_lt_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_ne : a ≠ b) :
    nodeCount (mergePair a b z fz t) < nodeCount t := by
  induction h_sib with
  | here fa fb =>
    simp [mergePair, nodeCount]
  | here' fa fb =>
    simp [mergePair, nodeCount]
  | inLeft l r h_sib_l ih =>
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      have h_l : nodeCount (mergePair a b z fz (htInner ll lr)) < nodeCount (htInner ll lr) := ih
      have h_r : nodeCount (mergePair a b z fz r) ≤ nodeCount r := nodeCount_mergePair_le a b z fz r
      simp [nodeCount] at h_l h_r ⊢
      have hm : mergePair a b z fz (htInner (htInner ll lr) r) =
        htInner (mergePair a b z fz (htInner ll lr)) (mergePair a b z fz r) := by simp [mergePair]
      rw [hm]; simp [nodeCount]
      omega
  | inRight l r h_sib_r ih =>
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      have h_l : nodeCount (mergePair a b z fz l) ≤ nodeCount l := nodeCount_mergePair_le a b z fz l
      have h_r : nodeCount (mergePair a b z fz (htInner rl rr)) < nodeCount (htInner rl rr) := ih
      simp [nodeCount] at h_l h_r ⊢
      have hm : mergePair a b z fz (htInner l (htInner rl rr)) =
        htInner (mergePair a b z fz l) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
      rw [hm]; simp [nodeCount]
      omega

lemma rootFreq_mergePair_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b) (h_fz : fz = freqOf a t + freqOf b t) :
    rootFreq (mergePair a b z fz t) = rootFreq t := by
  induction h_sib with
  | here fa fb =>
    simp [mergePair, rootFreq, freqOf, h_ne, h_ne.symm, h_fz]
  | here' fa fb =>
    simp [mergePair, rootFreq, freqOf, h_ne, h_ne.symm, h_fz]; omega
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    -- From disjointness: freqOf a r = 0 and freqOf b r = 0, so h_fz applies to l
    have h_fz_l : fz = freqOf a l + freqOf b l := by
      rw [freqOf, freqOf, freqOf_eq_zero_of_not_mem a r ha_r, freqOf_eq_zero_of_not_mem b r hb_r] at h_fz
      simpa [add_comm, add_left_comm, add_assoc] using h_fz
    have h_merge_r : mergePair a b z fz r = r := mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l := ih hcl h_fz_l
    -- Expand mergePair on htInner l r. Since areSiblings a b l, l cannot be htLeaf.
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, rootFreq, h_merge_r, h_root_l]
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_fz_r : fz = freqOf a r + freqOf b r := by
      rw [freqOf, freqOf, freqOf_eq_zero_of_not_mem a l ha_l, freqOf_eq_zero_of_not_mem b l hb_l] at h_fz
      simpa [add_comm, add_left_comm, add_assoc] using h_fz
    have h_merge_l : mergePair a b z fz l = l := mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r := ih hcr h_fz_r
    -- Expand mergePair. Since areSiblings a b r, r cannot be htLeaf.
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, rootFreq, h_merge_l, h_root_r]

lemma cost_mergePair_of_areSiblings (t : HuffTree) (a b z fa fb : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b)
    (h_fa : freqOf a t = fa) (h_fb : freqOf b t = fb) (h_fz : fz = fa + fb) :
    (cost (mergePair a b z fz t) : ℤ) = (cost t : ℤ) - (fa : ℤ) - (fb : ℤ) := by
  revert h_cons h_fa h_fb h_fz
  induction h_sib with
  | here fa' fb' =>
    intro h_cons h_fa h_fb h_fz
    have h_fa_val : freqOf a (htInner (htLeaf a fa') (htLeaf b fb')) = fa' := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_fb_val : freqOf b (htInner (htLeaf a fa') (htLeaf b fb')) = fb' := by
      simp [freqOf, h_ne, h_ne.symm]
    rw [h_fa_val] at h_fa; rw [h_fb_val] at h_fb; subst h_fa; subst h_fb
    have h_cost_merged : cost (mergePair a b z fz (htInner (htLeaf a fa') (htLeaf b fb'))) = 0 := by
      simp [mergePair, cost]
    have h_cost_t : cost (htInner (htLeaf a fa') (htLeaf b fb')) = fa' + fb' := by
      simp [cost, rootFreq]
    rw [h_cost_merged, h_cost_t]; push_cast; omega
  | here' fa' fb' =>
    intro h_cons h_fa h_fb h_fz
    have h_fa_val : freqOf a (htInner (htLeaf b fb') (htLeaf a fa')) = fa' := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_fb_val : freqOf b (htInner (htLeaf b fb') (htLeaf a fa')) = fb' := by
      simp [freqOf, h_ne, h_ne.symm]
    rw [h_fa_val] at h_fa; rw [h_fb_val] at h_fb; subst h_fa; subst h_fb
    have h_cost_merged : cost (mergePair a b z fz (htInner (htLeaf b fb') (htLeaf a fa'))) = 0 := by
      simp [mergePair, cost]
    have h_cost_t : cost (htInner (htLeaf b fb') (htLeaf a fa')) = fa' + fb' := by
      simp [cost, rootFreq]; omega
    rw [h_cost_merged, h_cost_t]; push_cast; omega
  | inLeft l r h_sib_l ih =>
    intro h_cons h_fa h_fb h_fz
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_l_a : freqOf a l = fa := by
      rw [← h_fa, freqOf, freqOf_eq_zero_of_not_mem a r ha_r]; simp
    have h_freq_l_b : freqOf b l = fb := by
      rw [← h_fb, freqOf, freqOf_eq_zero_of_not_mem b r hb_r]; simp
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l :=
      rootFreq_mergePair_of_areSiblings l a b z fz h_sib_l hcl h_ne (by rw [h_freq_l_a, h_freq_l_b]; exact h_fz)
    have h_cost_l : (cost (mergePair a b z fz l) : ℤ) = (cost l : ℤ) - (fa : ℤ) - (fb : ℤ) :=
      ih hcl h_freq_l_a h_freq_l_b h_fz
    have h_cost_r : cost (mergePair a b z fz r) = cost r := by
      simp [mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r]
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r := by
      simp [mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r]
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, cost, h_cost_l, h_cost_r, h_root_l, h_root_r]; ring
  | inRight l r h_sib_r ih =>
    intro h_cons h_fa h_fb h_fz
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_r_a : freqOf a r = fa := by
      rw [← h_fa, freqOf, freqOf_eq_zero_of_not_mem a l ha_l]; simp
    have h_freq_r_b : freqOf b r = fb := by
      rw [← h_fb, freqOf, freqOf_eq_zero_of_not_mem b l hb_l]; simp
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r :=
      rootFreq_mergePair_of_areSiblings r a b z fz h_sib_r hcr h_ne (by rw [h_freq_r_a, h_freq_r_b]; exact h_fz)
    have h_cost_r : (cost (mergePair a b z fz r) : ℤ) = (cost r : ℤ) - (fa : ℤ) - (fb : ℤ) :=
      ih hcr h_freq_r_a h_freq_r_b h_fz
    have h_cost_l : cost (mergePair a b z fz l) = cost l := by
      simp [mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l]
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l := by
      simp [mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l]
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, cost, h_cost_l, h_cost_r, h_root_l, h_root_r]; ring

lemma alphabet_mergePair_subset (a b z fz : ℕ) (t : HuffTree) :
    alphabet (mergePair a b z fz t) ⊆ alphabet t ∪ {z} := by
  induction t with
  | htLeaf s f => simp [mergePair]
  | htInner l r ihl ihr =>
    intro x hx
    cases l with
    | htLeaf sl fl =>
      cases r with
      | htLeaf sr fr =>
        by_cases hpair : (sl = a ∧ sr = b) ∨ (sl = b ∧ sr = a)
        · -- mergePair returns htLeaf z fz
          have h_merge_val : mergePair a b z fz (htInner (htLeaf sl fl) (htLeaf sr fr)) = htLeaf z fz := by
            simp [mergePair, hpair]
          have hx' : x ∈ alphabet (htLeaf z fz) := by rwa [h_merge_val] at hx
          rcases Finset.mem_singleton.mp hx' with rfl
          simp
        · -- mergePair returns htInner (htLeaf sl fl) (htLeaf sr fr)
          have h_merge_val : mergePair a b z fz (htInner (htLeaf sl fl) (htLeaf sr fr)) =
                             htInner (htLeaf sl fl) (htLeaf sr fr) := by
            simp [mergePair, hpair]
          have hx' : x ∈ alphabet (htInner (htLeaf sl fl) (htLeaf sr fr)) := by rwa [h_merge_val] at hx
          -- hx' : x ∈ {sl} ∪ {sr}, goal: x ∈ ({sl} ∪ {sr}) ∪ {z}
          exact Finset.mem_union_left _ hx'
      | htInner rl rr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · apply Finset.mem_union_left; apply Finset.mem_union_left; exact hx_l
        · have h := ihr hx_r
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_right; exact h'
          · apply Finset.mem_union_right; exact h'
    | htInner ll lr =>
      cases r with
      | htLeaf sr fr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · have h := ihl hx_l
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_left; exact h'
          · apply Finset.mem_union_right; exact h'
        · apply Finset.mem_union_left; apply Finset.mem_union_right; exact hx_r
      | htInner rl rr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · have h := ihl hx_l
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_left; exact h'
          · apply Finset.mem_union_right; exact h'
        · have h := ihr hx_r
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_right; exact h'
          · apply Finset.mem_union_right; exact h'

lemma consistent_mergePair_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (hz_fresh : z ∉ alphabet t) :
    consistent (mergePair a b z fz t) := by
  induction h_sib with
  | here fa fb => simp [mergePair, consistent]
  | here' fa fb => simp [mergePair, consistent]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have h_merge_r : mergePair a b z fz r = r :=
      mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r
    have h_l := ih hcl hz_l
    have h_disjoint_merge : Disjoint (alphabet (mergePair a b z fz l)) (alphabet r) := by
      have h_sub : alphabet (mergePair a b z fz l) ⊆ alphabet l ∪ {z} :=
        alphabet_mergePair_subset a b z fz l
      have h_disj_sup : Disjoint (alphabet l ∪ {z}) (alphabet r) := by
        rw [Finset.disjoint_union_left]
        exact ⟨hd, by rw [Finset.disjoint_singleton_left]; exact hz_r⟩
      exact Finset.disjoint_of_subset_left h_sub h_disj_sup
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, h_merge_r, consistent]
      exact ⟨h_l, hcr, h_disjoint_merge⟩
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have h_merge_l : mergePair a b z fz l = l :=
      mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l
    have h_r := ih hcr hz_r
    have h_disjoint_merge : Disjoint (alphabet l) (alphabet (mergePair a b z fz r)) := by
      have h_sub : alphabet (mergePair a b z fz r) ⊆ alphabet r ∪ {z} :=
        alphabet_mergePair_subset a b z fz r
      have h_disj_sup : Disjoint (alphabet l) (alphabet r ∪ {z}) := by
        rw [Finset.disjoint_union_right]
        exact ⟨hd, by rw [Finset.disjoint_singleton_right]; exact hz_l⟩
      exact Finset.disjoint_of_subset_right h_sub h_disj_sup
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, h_merge_l, consistent]
      exact ⟨hcl, h_r, h_disjoint_merge⟩

lemma freqOf_mergePair_of_areSiblings (t : HuffTree) (a b z : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (hz_fresh : z ∉ alphabet t) (s : ℕ) :
    freqOf s (mergePair a b z (freqOf a t + freqOf b t) t) =
    if s = z then freqOf a t + freqOf b t
    else if s = a ∨ s = b then 0
    else freqOf s t := by
  cases h_sib with
  | here fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    have h_ne : a ≠ b := by
      intro heq; subst heq
      have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
      simp [alphabet] at h_empty
    have hz_ne_a : z ≠ a := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have hz_ne_b : z ≠ b := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have h_freq_sum : freqOf a (htInner (htLeaf a fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf a fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_merge_val : mergePair a b z (freqOf a (htInner (htLeaf a fa) (htLeaf b fb)) +
                                        freqOf b (htInner (htLeaf a fa) (htLeaf b fb)))
                                        (htInner (htLeaf a fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsa : s = a
      · subst s; simp
      · by_cases hsb : s = b
        · subst s; simp
        · have h_freq_s : freqOf s (htInner (htLeaf a fa) (htLeaf b fb)) = 0 := by
            simp [freqOf, hsa, hsb, Ne.symm hsa, Ne.symm hsb]
          simp [hsa, hsb, h_freq_s]
  | here' fb_a fa_a =>
    rcases h_cons with ⟨_, _, hd⟩
    have h_ne : a ≠ b := by
      intro heq; subst heq
      have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
      simp [alphabet] at h_empty
    have hz_ne_a : z ≠ a := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have hz_ne_b : z ≠ b := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have h_freq_sum : freqOf a (htInner (htLeaf b fa_a) (htLeaf a fb_a)) +
                     freqOf b (htInner (htLeaf b fa_a) (htLeaf a fb_a)) = fa_a + fb_a := by
      simp [freqOf, h_ne, h_ne.symm]; omega
    have h_merge_val : mergePair a b z (freqOf a (htInner (htLeaf b fa_a) (htLeaf a fb_a)) +
                                        freqOf b (htInner (htLeaf b fa_a) (htLeaf a fb_a)))
                                        (htInner (htLeaf b fa_a) (htLeaf a fb_a)) =
                       htLeaf z (fa_a + fb_a) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsa : s = a
      · subst s; simp
      · by_cases hsb : s = b
        · subst s; simp
        · have h_freq_s : freqOf s (htInner (htLeaf b fa_a) (htLeaf a fb_a)) = 0 := by
            simp [freqOf, hsa, hsb, Ne.symm hsa, Ne.symm hsb]
          simp [hsa, hsb, h_freq_s]
  | inLeft l r h_sib_l =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have h_freq_ar : freqOf a r = 0 := freqOf_eq_zero_of_not_mem _ _ ha_r
    have h_freq_br : freqOf b r = 0 := freqOf_eq_zero_of_not_mem _ _ hb_r
    have h_freq_zr : freqOf z r = 0 := freqOf_eq_zero_of_not_mem _ _ hz_r
    cases l with
    | htLeaf _ _ => exfalso; cases h_sib_l
    | htInner ll lr =>
      -- t = htInner (htInner ll lr) r; compute freq sum
      let l' := htInner ll lr
      have h_fz_l : freqOf a (htInner (htInner ll lr) r) + freqOf b (htInner (htInner ll lr) r) =
                   freqOf a (htInner ll lr) + freqOf b (htInner ll lr) := by
        simp [freqOf, h_freq_ar, h_freq_br]
      rw [h_fz_l]
      have h_merge_r' : mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r = r :=
        mergePair_eq_self_of_not_mem a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r ha_r hb_r
      have h_freq_l := freqOf_mergePair_of_areSiblings (htInner ll lr) a b z h_sib_l hcl hz_l s
      have h_mp : mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr))
                                 (htInner (htInner ll lr) r) =
                 htInner (mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) (htInner ll lr))
                        (mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r) := by
        delta mergePair; simp
      rw [h_mp, h_merge_r']
      -- Goal: freqOf s (htInner (mergePair ... (htInner ll lr)) r) = ...
      -- Expand only the top-level freqOf
      conv => lhs; rw [freqOf]
      -- Now freqOf s (mergePair ... (htInner ll lr)) + freqOf s r = ...
      rw [h_freq_l]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zr]
      · by_cases hsa : s = a
        · subst s; simp [h_freq_ar]
        · by_cases hsb : s = b
          · subst s; simp [h_freq_br]
          · simp [hsz, hsa, hsb, freqOf]
  | inRight l r h_sib_r =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have h_freq_al : freqOf a l = 0 := freqOf_eq_zero_of_not_mem _ _ ha_l
    have h_freq_bl : freqOf b l = 0 := freqOf_eq_zero_of_not_mem _ _ hb_l
    have h_freq_zl : freqOf z l = 0 := freqOf_eq_zero_of_not_mem _ _ hz_l
    cases r with
    | htLeaf _ _ => exfalso; cases h_sib_r
    | htInner rl rr =>
      -- t = htInner l (htInner rl rr); compute freq sum
      have h_fz_r : freqOf a (htInner l (htInner rl rr)) + freqOf b (htInner l (htInner rl rr)) =
                   freqOf a (htInner rl rr) + freqOf b (htInner rl rr) := by
        simp [freqOf, h_freq_al, h_freq_bl]
      rw [h_fz_r]
      have h_merge_l' : mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l = l :=
        mergePair_eq_self_of_not_mem a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l ha_l hb_l
      have h_freq_r := freqOf_mergePair_of_areSiblings (htInner rl rr) a b z h_sib_r hcr hz_r s
      have h_mp : mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr))
                                 (htInner l (htInner rl rr)) =
                 htInner (mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l)
                        (mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) (htInner rl rr)) := by
        delta mergePair; simp
      rw [h_mp, h_merge_l']
      conv => lhs; rw [freqOf]
      rw [h_freq_r]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zl]
      · by_cases hsa : s = a
        · subst s; simp [h_freq_al]
        · by_cases hsb : s = b
          · subst s; simp [h_freq_bl]
          · simp [hsz, hsa, hsb, freqOf]
