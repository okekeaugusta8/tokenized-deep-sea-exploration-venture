;; Exploration Shares Smart Contract
;; Tokenized Deep Sea Exploration Venture
;; Manages fractional ownership and revenue distribution

;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-AUTHORIZED (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-VENTURE-NOT-FOUND (err u203))
(define-constant ERR-INSUFFICIENT-SHARES (err u204))
(define-constant ERR-VENTURE-INACTIVE (err u205))
(define-constant ERR-INVALID-RECIPIENT (err u206))
(define-constant ERR-REVENUE-ALREADY-DISTRIBUTED (err u207))
(define-constant ERR-NO-SHARES-OWNED (err u208))

;; Share Configuration
(define-constant SHARE-DECIMALS u6)
(define-constant MIN-SHARE-AMOUNT u1000000) ;; 1 share = 1,000,000 units
(define-constant MAX-VENTURES u1000)

;; Venture Information
(define-map ventures
  { venture-id: uint }
  {
    name: (string-ascii 128),
    total-shares: uint,
    shares-issued: uint,
    venture-status: (string-ascii 32),
    created-at: uint,
    creator: principal,
    total-revenue: uint,
    revenue-per-share: uint,
    last-distribution: uint
  }
)

;; Share Ownership
(define-map share-balances
  { venture-id: uint, owner: principal }
  { balance: uint }
)

;; Venture Participants
(define-map venture-participants
  { venture-id: uint, participant: principal }
  { 
    joined-at: uint,
    initial-shares: uint,
    current-shares: uint,
    total-claimed: uint
  }
)

;; Revenue Distribution Records
(define-map revenue-distributions
  { venture-id: uint, distribution-id: uint }
  {
    amount: uint,
    distribution-date: uint,
    per-share-amount: uint,
    total-participants: uint
  }
)

;; User Holdings Summary
(define-map user-portfolio
  { user: principal }
  {
    total-ventures: uint,
    total-shares: uint,
    total-revenue-claimed: uint
  }
)

;; Global State Variables
(define-data-var venture-counter uint u0)
(define-data-var total-active-ventures uint u0)
(define-data-var total-shares-issued uint u0)
(define-data-var contract-paused bool false)

;; Authorization Functions
(define-private (is-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-contract-active)
  (not (var-get contract-paused))
)

;; Venture Management Functions
(define-public (create-venture 
    (name (string-ascii 128))
    (total-shares uint))
  (let 
    (
      (venture-id (+ (var-get venture-counter) u1))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> total-shares u0) ERR-INVALID-AMOUNT)
    (asserts! (< venture-id MAX-VENTURES) ERR-INVALID-AMOUNT)
    
    ;; Create venture record
    (map-set ventures
      { venture-id: venture-id }
      {
        name: name,
        total-shares: total-shares,
        shares-issued: u0,
        venture-status: "active",
        created-at: block-height,
        creator: tx-sender,
        total-revenue: u0,
        revenue-per-share: u0,
        last-distribution: u0
      }
    )
    
    ;; Update counters
    (var-set venture-counter venture-id)
    (var-set total-active-ventures (+ (var-get total-active-ventures) u1))
    
    (ok venture-id)
  )
)

(define-public (mint-shares 
    (venture-id uint) 
    (amount uint) 
    (recipient principal))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
      (current-issued (get shares-issued venture))
      (total-allowed (get total-shares venture))
      (current-balance (get-share-balance venture-id recipient))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= amount MIN-SHARE-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get venture-status venture) "active") ERR-VENTURE-INACTIVE)
    (asserts! (<= (+ current-issued amount) total-allowed) ERR-INVALID-AMOUNT)
    
    ;; Update share balance
    (map-set share-balances
      { venture-id: venture-id, owner: recipient }
      { balance: (+ current-balance amount) }
    )
    
    ;; Update venture shares issued
    (map-set ventures
      { venture-id: venture-id }
      (merge venture { shares-issued: (+ current-issued amount) })
    )
    
    ;; Add or update participant record
    (update-participant-record venture-id recipient amount)
    
    ;; Update user portfolio
    (update-user-portfolio recipient amount)
    
    ;; Update global counter
    (var-set total-shares-issued (+ (var-get total-shares-issued) amount))
    
    (ok true)
  )
)

(define-public (transfer-shares 
    (venture-id uint)
    (amount uint) 
    (sender principal) 
    (recipient principal))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
      (sender-balance (get-share-balance venture-id sender))
      (recipient-balance (get-share-balance venture-id recipient))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-SHARES)
    (asserts! (is-eq (get venture-status venture) "active") ERR-VENTURE-INACTIVE)
    
    ;; Update sender balance
    (map-set share-balances
      { venture-id: venture-id, owner: sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update recipient balance
    (map-set share-balances
      { venture-id: venture-id, owner: recipient }
      { balance: (+ recipient-balance amount) }
    )
    
    ;; Update participant records
    (update-participant-shares venture-id sender (- sender-balance amount))
    (update-participant-record venture-id recipient amount)
    
    (ok true)
  )
)

;; Revenue Distribution Functions
(define-public (distribute-revenue 
    (venture-id uint)
    (total-revenue uint))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
      (total-issued (get shares-issued venture))
      (per-share-amount (/ total-revenue total-issued))
    )
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (asserts! (> total-revenue u0) ERR-INVALID-AMOUNT)
    (asserts! (> total-issued u0) ERR-INVALID-AMOUNT)
    
    ;; Update venture revenue information
    (map-set ventures
      { venture-id: venture-id }
      (merge venture 
        {
          total-revenue: (+ (get total-revenue venture) total-revenue),
          revenue-per-share: (+ (get revenue-per-share venture) per-share-amount),
          last-distribution: block-height
        }
      )
    )
    
    ;; Record distribution
    (map-set revenue-distributions
      { venture-id: venture-id, distribution-id: block-height }
      {
        amount: total-revenue,
        distribution-date: block-height,
        per-share-amount: per-share-amount,
        total-participants: u0 ;; This would be calculated in a real implementation
      }
    )
    
    (ok per-share-amount)
  )
)

(define-public (claim-revenue (venture-id uint))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
      (user-shares (get-share-balance venture-id tx-sender))
      (revenue-per-share (get revenue-per-share venture))
      (claimable-amount (* user-shares revenue-per-share))
      (participant (unwrap! (map-get? venture-participants { venture-id: venture-id, participant: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> user-shares u0) ERR-NO-SHARES-OWNED)
    (asserts! (> claimable-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update participant claimed amount
    (map-set venture-participants
      { venture-id: venture-id, participant: tx-sender }
      (merge participant { total-claimed: (+ (get total-claimed participant) claimable-amount) })
    )
    
    ;; Update user portfolio
    (let 
      (
        (portfolio (default-to 
          { total-ventures: u0, total-shares: u0, total-revenue-claimed: u0 }
          (map-get? user-portfolio { user: tx-sender })
        ))
      )
      (map-set user-portfolio
        { user: tx-sender }
        (merge portfolio { total-revenue-claimed: (+ (get total-revenue-claimed portfolio) claimable-amount) })
      )
    )
    
    (ok claimable-amount)
  )
)

;; Query Functions
(define-read-only (get-venture-details (venture-id uint))
  (map-get? ventures { venture-id: venture-id })
)

(define-read-only (get-share-balance (venture-id uint) (owner principal))
  (default-to u0 (get balance (map-get? share-balances { venture-id: venture-id, owner: owner })))
)

(define-read-only (get-participant-info (venture-id uint) (participant principal))
  (map-get? venture-participants { venture-id: venture-id, participant: participant })
)

(define-read-only (get-user-portfolio (user principal))
  (map-get? user-portfolio { user: user })
)

(define-read-only (get-venture-count)
  (var-get venture-counter)
)

(define-read-only (get-total-active-ventures)
  (var-get total-active-ventures)
)

(define-read-only (get-total-shares-issued)
  (var-get total-shares-issued)
)

(define-read-only (get-revenue-distribution (venture-id uint) (distribution-id uint))
  (map-get? revenue-distributions { venture-id: venture-id, distribution-id: distribution-id })
)

;; Administrative Functions
(define-public (pause-contract)
  (begin
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (deactivate-venture (venture-id uint))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
    )
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (asserts! (is-eq (get venture-status venture) "active") ERR-VENTURE-INACTIVE)
    
    (map-set ventures
      { venture-id: venture-id }
      (merge venture { venture-status: "inactive" })
    )
    
    (var-set total-active-ventures (- (var-get total-active-ventures) u1))
    
    (ok true)
  )
)

(define-read-only (is-paused)
  (var-get contract-paused)
)

;; Helper Functions (returning void)
(define-private (update-participant-record (venture-id uint) (participant principal) (shares uint))
  (let 
    (
      (existing (map-get? venture-participants { venture-id: venture-id, participant: participant }))
    )
    (match existing
      current-record
      (map-set venture-participants
        { venture-id: venture-id, participant: participant }
        (merge current-record { current-shares: (+ (get current-shares current-record) shares) })
      )
      (map-set venture-participants
        { venture-id: venture-id, participant: participant }
        {
          joined-at: block-height,
          initial-shares: shares,
          current-shares: shares,
          total-claimed: u0
        }
      )
    )
  )
)

(define-private (update-participant-shares (venture-id uint) (participant principal) (new-balance uint))
  (let 
    (
      (existing (map-get? venture-participants { venture-id: venture-id, participant: participant }))
    )
    (match existing
      current-record
      (map-set venture-participants
        { venture-id: venture-id, participant: participant }
        (merge current-record { current-shares: new-balance })
      )
      false ;; Do nothing if participant doesn't exist
    )
  )
)

(define-private (update-user-portfolio (user principal) (shares uint))
  (let 
    (
      (portfolio (default-to 
        { total-ventures: u0, total-shares: u0, total-revenue-claimed: u0 }
        (map-get? user-portfolio { user: user })
      ))
    )
    (map-set user-portfolio
      { user: user }
      {
        total-ventures: (+ (get total-ventures portfolio) u1),
        total-shares: (+ (get total-shares portfolio) shares),
        total-revenue-claimed: (get total-revenue-claimed portfolio)
      }
    )
  )
)

;; Calculation Helpers
(define-read-only (calculate-ownership-percentage (venture-id uint) (owner principal))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) (err u0)))
      (user-shares (get-share-balance venture-id owner))
      (total-issued (get shares-issued venture))
    )
    (if (> total-issued u0)
      (ok (/ (* user-shares u10000) total-issued)) ;; Returns percentage * 100 (e.g., 1500 = 15.00%)
      (ok u0)
    )
  )
)

(define-read-only (calculate-potential-revenue (venture-id uint) (owner principal))
  (let 
    (
      (venture (unwrap! (map-get? ventures { venture-id: venture-id }) (err u0)))
      (user-shares (get-share-balance venture-id owner))
      (revenue-per-share (get revenue-per-share venture))
    )
    (ok (* user-shares revenue-per-share))
  )
)
