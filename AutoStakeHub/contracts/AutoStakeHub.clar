;; Autonomous Decentralized Staking Protocol
;; This smart contract implements a fully decentralized staking protocol with time-locked deposits,
;; automated reward distribution, penalty mechanisms for early withdrawal, and flexible staking tiers.
;; Users can stake STX tokens to earn rewards based on their stake amount and lock duration.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-staked (err u202))
(define-constant err-insufficient-stake (err u203))
(define-constant err-lock-period-active (err u204))
(define-constant err-no-rewards (err u205))
(define-constant err-invalid-amount (err u206))
(define-constant err-invalid-tier (err u207))
(define-constant err-transfer-failed (err u208))
(define-constant err-calculation-error (err u209))

;; Staking tier configuration (days to basis points APY)
(define-constant tier-30-days u30)
(define-constant tier-90-days u90)
(define-constant tier-180-days u180)
(define-constant tier-365-days u365)

(define-constant apy-30-days u500)    ;; 5% APY
(define-constant apy-90-days u1000)   ;; 10% APY
(define-constant apy-180-days u1500)  ;; 15% APY
(define-constant apy-365-days u2000)  ;; 20% APY

(define-constant basis-points u10000)
(define-constant blocks-per-day u144) ;; Approximate blocks per day
(define-constant early-withdrawal-penalty u2000) ;; 20% penalty

;; data maps and vars
;; Track individual staker information
(define-map stakes
  { staker: principal }
  {
    amount: uint,
    start-block: uint,
    lock-period-days: uint,
    tier-apy: uint,
    last-claim-block: uint,
    total-claimed: uint
  }
)

;; Track protocol-wide statistics
(define-data-var total-staked uint u0)
(define-data-var total-stakers uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var protocol-active bool true)
(define-data-var reward-pool uint u0)

;; Emergency pause mechanism
(define-data-var emergency-pause bool false)

;; private functions
;; Calculate APY based on lock period tier
(define-private (get-tier-apy (lock-days uint))
  (if (is-eq lock-days tier-30-days)
    apy-30-days
    (if (is-eq lock-days tier-90-days)
      apy-90-days
      (if (is-eq lock-days tier-180-days)
        apy-180-days
        (if (is-eq lock-days tier-365-days)
          apy-365-days
          u0
        )
      )
    )
  )
)

;; Validate staking tier selection
(define-private (is-valid-tier (lock-days uint))
  (or
    (is-eq lock-days tier-30-days)
    (or
      (is-eq lock-days tier-90-days)
      (or
        (is-eq lock-days tier-180-days)
        (is-eq lock-days tier-365-days)
      )
    )
  )
)

;; Calculate pending rewards for a staker
(define-private (calculate-rewards-internal (staker principal))
  (match (map-get? stakes { staker: staker })
    stake-data
      (let
        (
          (blocks-passed (- block-height (get last-claim-block stake-data)))
          (stake-amount (get amount stake-data))
          (apy (get tier-apy stake-data))
          (lock-days (get lock-period-days stake-data))
          (total-lock-blocks (* lock-days blocks-per-day))
        )
        ;; Reward = (stake * APY * blocks-passed) / (basis-points * total-lock-blocks)
        (ok (/ (* (* stake-amount apy) blocks-passed) (* basis-points total-lock-blocks)))
      )
    (ok u0)
  )
)

;; Check if lock period has expired
(define-private (is-lock-expired (staker principal))
  (match (map-get? stakes { staker: staker })
    stake-data
      (let
        (
          (lock-blocks (* (get lock-period-days stake-data) blocks-per-day))
          (elapsed-blocks (- block-height (get start-block stake-data)))
        )
        (>= elapsed-blocks lock-blocks)
      )
    false
  )
)

;; public functions
;; Stake tokens with selected lock period tier
(define-public (stake (amount uint) (lock-days uint))
  (let
    (
      (existing-stake (map-get? stakes { staker: tx-sender }))
      (tier-apy (get-tier-apy lock-days))
    )
    ;; Validations
    (asserts! (var-get protocol-active) err-owner-only)
    (asserts! (not (var-get emergency-pause)) err-owner-only)
    (asserts! (is-none existing-stake) err-already-staked)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-valid-tier lock-days) err-invalid-tier)
    
    ;; Transfer tokens to contract (in production, uncomment this)
    ;; (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Record stake
    (map-set stakes
      { staker: tx-sender }
      {
        amount: amount,
        start-block: block-height,
        lock-period-days: lock-days,
        tier-apy: tier-apy,
        last-claim-block: block-height,
        total-claimed: u0
      }
    )
    
    ;; Update global statistics
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set total-stakers (+ (var-get total-stakers) u1))
    
    (ok true)
  )
)

;; Claim accumulated rewards without unstaking
(define-public (claim-rewards)
  (let
    (
      (stake-data (unwrap! (map-get? stakes { staker: tx-sender }) err-not-found))
      (pending-rewards (unwrap! (calculate-rewards-internal tx-sender) err-calculation-error))
    )
    ;; Validations
    (asserts! (not (var-get emergency-pause)) err-owner-only)
    (asserts! (> pending-rewards u0) err-no-rewards)
    
    ;; Update stake data with new claim block
    (map-set stakes
      { staker: tx-sender }
      (merge stake-data {
        last-claim-block: block-height,
        total-claimed: (+ (get total-claimed stake-data) pending-rewards)
      })
    )
    
    ;; Transfer rewards (in production, uncomment this)
    ;; (try! (as-contract (stx-transfer? pending-rewards tx-sender tx-sender)))
    
    ;; Update statistics
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) pending-rewards))
    
    (ok pending-rewards)
  )
)

;; Unstake tokens after lock period expires
(define-public (unstake)
  (let
    (
      (stake-data (unwrap! (map-get? stakes { staker: tx-sender }) err-not-found))
      (stake-amount (get amount stake-data))
      (pending-rewards (unwrap! (calculate-rewards-internal tx-sender) err-calculation-error))
      (total-return (+ stake-amount pending-rewards))
    )
    ;; Validations
    (asserts! (is-lock-expired tx-sender) err-lock-period-active)
    
    ;; Remove stake
    (map-delete stakes { staker: tx-sender })
    
    ;; Transfer principal + rewards (in production, uncomment this)
    ;; (try! (as-contract (stx-transfer? total-return tx-sender tx-sender)))
    
    ;; Update statistics
    (var-set total-staked (- (var-get total-staked) stake-amount))
    (var-set total-stakers (- (var-get total-stakers) u1))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) pending-rewards))
    
    (ok total-return)
  )
)

;; Emergency unstake with penalty (before lock period expires)
(define-public (emergency-unstake)
  (let
    (
      (stake-data (unwrap! (map-get? stakes { staker: tx-sender }) err-not-found))
      (stake-amount (get amount stake-data))
      (penalty-amount (/ (* stake-amount early-withdrawal-penalty) basis-points))
      (return-amount (- stake-amount penalty-amount))
    )
    ;; Validations
    (asserts! (not (is-lock-expired tx-sender)) err-lock-period-active)
    
    ;; Remove stake
    (map-delete stakes { staker: tx-sender })
    
    ;; Transfer reduced amount (penalty stays in contract)
    ;; (try! (as-contract (stx-transfer? return-amount tx-sender tx-sender)))
    
    ;; Update statistics
    (var-set total-staked (- (var-get total-staked) stake-amount))
    (var-set total-stakers (- (var-get total-stakers) u1))
    (var-set reward-pool (+ (var-get reward-pool) penalty-amount))
    
    (ok return-amount)
  )
)

;; Admin function to fund reward pool
(define-public (fund-reward-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set reward-pool (+ (var-get reward-pool) amount))
    
    (ok true)
  )
)

;; Admin function to toggle emergency pause
(define-public (toggle-emergency-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-pause (not (var-get emergency-pause)))
    (ok (var-get emergency-pause))
  )
)

;; Advanced compound staking with automatic reward reinvestment and tier upgrade
;; This function allows stakers to compound their rewards back into their stake,
;; automatically calculating new APY based on extended lock period and increased principal.
;; Provides optimal capital efficiency and maximizes long-term returns for committed stakers.
(define-public (compound-stake-with-tier-upgrade (additional-lock-days uint))
  (let
    (
      (stake-data (unwrap! (map-get? stakes { staker: tx-sender }) err-not-found))
      (pending-rewards (unwrap! (calculate-rewards-internal tx-sender) err-calculation-error))
      (current-amount (get amount stake-data))
      (current-lock-days (get lock-period-days stake-data))
      (blocks-elapsed (- block-height (get start-block stake-data)))
      (current-lock-blocks (* current-lock-days blocks-per-day))
      (remaining-lock-blocks (if (> current-lock-blocks blocks-elapsed)
                                (- current-lock-blocks blocks-elapsed)
                                u0))
    )
    ;; Validations
    (asserts! (not (var-get emergency-pause)) err-owner-only)
    (asserts! (> pending-rewards u0) err-no-rewards)
    (asserts! (is-valid-tier additional-lock-days) err-invalid-tier)
    (asserts! (>= additional-lock-days current-lock-days) err-invalid-tier)
    
    ;; Calculate new parameters
    (let
      (
        (new-principal (+ current-amount pending-rewards))
        (new-lock-days additional-lock-days)
        (new-apy (get-tier-apy new-lock-days))
        (new-start-block block-height)
      )
      ;; Update stake with compounded amount and new tier
      (map-set stakes
        { staker: tx-sender }
        {
          amount: new-principal,
          start-block: new-start-block,
          lock-period-days: new-lock-days,
          tier-apy: new-apy,
          last-claim-block: block-height,
          total-claimed: (+ (get total-claimed stake-data) pending-rewards)
        }
      )
      
      ;; Update global statistics
      (var-set total-staked (+ (var-get total-staked) pending-rewards))
      (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) pending-rewards))
      
      ;; Return compound summary
      (ok {
        compounded-amount: pending-rewards,
        new-principal: new-principal,
        previous-apy: (get tier-apy stake-data),
        new-apy: new-apy,
        new-lock-period: new-lock-days,
        estimated-maturity-block: (+ block-height (* new-lock-days blocks-per-day))
      })
    )
  )
)

;; Read-only functions
(define-read-only (get-stake-info (staker principal))
  (ok (map-get? stakes { staker: staker }))
)

(define-read-only (calculate-pending-rewards (staker principal))
  (calculate-rewards-internal staker)
)

(define-read-only (get-protocol-stats)
  (ok {
    total-staked: (var-get total-staked),
    total-stakers: (var-get total-stakers),
    total-rewards-distributed: (var-get total-rewards-distributed),
    reward-pool: (var-get reward-pool),
    protocol-active: (var-get protocol-active),
    emergency-pause: (var-get emergency-pause)
  })
)

(define-read-only (check-lock-status (staker principal))
  (ok {
    is-expired: (is-lock-expired staker),
    can-unstake: (is-lock-expired staker)
  })
)



