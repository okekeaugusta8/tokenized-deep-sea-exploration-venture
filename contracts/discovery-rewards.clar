;; Discovery Rewards Smart Contract
;; Tokenized Deep Sea Exploration Venture
;; Manages discovery tokens and reward distribution system

;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-DISCOVERY-TYPE (err u103))
(define-constant ERR-DISCOVERY-NOT-FOUND (err u104))
(define-constant ERR-ALREADY-CLAIMED (err u105))
(define-constant ERR-INSUFFICIENT-BALANCE (err u106))
(define-constant ERR-INVALID-RECIPIENT (err u107))

;; Token Configuration
(define-constant TOKEN-NAME "Deep Sea Discovery Token")
(define-constant TOKEN-SYMBOL "DSDT")
(define-constant TOKEN-DECIMALS u8)
(define-constant MAX-SUPPLY u1000000000) ;; 1 billion tokens max

;; Discovery Types and Multipliers
(define-map discovery-multipliers
  { discovery-type: (string-ascii 64) }
  { multiplier: uint }
)

;; Token Balances
(define-map token-balances
  { owner: principal }
  { balance: uint }
)

;; Discovery Records
(define-map discoveries
  { discovery-id: uint }
  {
    discoverer: principal,
    discovery-type: (string-ascii 64),
    reward-amount: uint,
    timestamp: uint,
    verified: bool,
    claimed: bool,
    description: (string-utf8 256)
  }
)

;; User Discovery Statistics
(define-map user-stats
  { user: principal }
  {
    total-discoveries: uint,
    total-rewards: uint,
    last-discovery-time: uint
  }
)

;; Global State Variables
(define-data-var total-supply uint u0)
(define-data-var discovery-counter uint u0)
(define-data-var total-discoveries uint u0)
(define-data-var contract-paused bool false)

;; Initialize default discovery types and multipliers
(map-set discovery-multipliers { discovery-type: "new-species" } { multiplier: u1000 })
(map-set discovery-multipliers { discovery-type: "mineral-deposit" } { multiplier: u2000 })
(map-set discovery-multipliers { discovery-type: "hydrothermal-vent" } { multiplier: u1500 })
(map-set discovery-multipliers { discovery-type: "underwater-formation" } { multiplier: u800 })
(map-set discovery-multipliers { discovery-type: "archaeological-artifact" } { multiplier: u3000 })
(map-set discovery-multipliers { discovery-type: "rare-ecosystem" } { multiplier: u2500 })

;; Authorization Functions
(define-private (is-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-contract-active)
  (not (var-get contract-paused))
)

;; Token Functions
(define-read-only (get-name)
  (ok TOKEN-NAME)
)

(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

(define-read-only (get-balance (who principal))
  (default-to u0 (get balance (map-get? token-balances { owner: who })))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

;; Core Discovery Functions
(define-public (award-discovery 
    (amount uint) 
    (discovery-type (string-ascii 64)) 
    (recipient principal)
    (description (string-utf8 256)))
  (let 
    (
      (current-id (+ (var-get discovery-counter) u1))
      (multiplier (get-discovery-multiplier discovery-type))
      (final-amount (* amount multiplier))
      (current-balance (get-balance recipient))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> multiplier u0) ERR-INVALID-DISCOVERY-TYPE)
    (asserts! (< (+ (var-get total-supply) final-amount) MAX-SUPPLY) ERR-INVALID-AMOUNT)
    
    ;; Record the discovery
    (map-set discoveries
      { discovery-id: current-id }
      {
        discoverer: recipient,
        discovery-type: discovery-type,
        reward-amount: final-amount,
        timestamp: block-height,
        verified: false,
        claimed: false,
        description: description
      }
    )
    
    ;; Update counters
    (var-set discovery-counter current-id)
    (var-set total-discoveries (+ (var-get total-discoveries) u1))
    
    ;; Update user statistics
    (update-user-stats recipient final-amount)
    
    (ok current-id)
  )
)

(define-public (verify-discovery (discovery-id uint))
  (let 
    (
      (discovery (unwrap! (map-get? discoveries { discovery-id: discovery-id }) ERR-DISCOVERY-NOT-FOUND))
    )
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (asserts! (not (get verified discovery)) ERR-ALREADY-CLAIMED)
    
    ;; Mark discovery as verified
    (map-set discoveries
      { discovery-id: discovery-id }
      (merge discovery { verified: true })
    )
    
    (ok true)
  )
)

(define-public (claim-rewards (discovery-id uint))
  (let 
    (
      (discovery (unwrap! (map-get? discoveries { discovery-id: discovery-id }) ERR-DISCOVERY-NOT-FOUND))
      (discoverer (get discoverer discovery))
      (reward-amount (get reward-amount discovery))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender discoverer) ERR-NOT-AUTHORIZED)
    (asserts! (get verified discovery) ERR-NOT-AUTHORIZED)
    (asserts! (not (get claimed discovery)) ERR-ALREADY-CLAIMED)
    
    ;; Mark as claimed
    (map-set discoveries
      { discovery-id: discovery-id }
      (merge discovery { claimed: true })
    )
    
    ;; Mint tokens to discoverer
    (mint-tokens reward-amount discoverer)
  )
)

;; Token Management Functions
(define-private (mint-tokens (amount uint) (recipient principal))
  (let 
    (
      (current-balance (get-balance recipient))
      (new-balance (+ current-balance amount))
      (new-supply (+ (var-get total-supply) amount))
    )
    (map-set token-balances
      { owner: recipient }
      { balance: new-balance }
    )
    (var-set total-supply new-supply)
    (ok true)
  )
)

(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (let 
    (
      (sender-balance (get-balance sender))
      (recipient-balance (get-balance recipient))
    )
    (asserts! (is-contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update balances
    (map-set token-balances
      { owner: sender }
      { balance: (- sender-balance amount) }
    )
    
    (map-set token-balances
      { owner: recipient }
      { balance: (+ recipient-balance amount) }
    )
    
    (ok true)
  )
)

;; Discovery Type Management
(define-public (set-discovery-multiplier (discovery-type (string-ascii 64)) (multiplier uint))
  (begin
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (asserts! (> multiplier u0) ERR-INVALID-AMOUNT)
    
    (map-set discovery-multipliers
      { discovery-type: discovery-type }
      { multiplier: multiplier }
    )
    
    (ok true)
  )
)

(define-read-only (get-discovery-multiplier (discovery-type (string-ascii 64)))
  (default-to u0 (get multiplier (map-get? discovery-multipliers { discovery-type: discovery-type })))
)

;; Statistics and Query Functions
(define-read-only (get-discovery-details (discovery-id uint))
  (map-get? discoveries { discovery-id: discovery-id })
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-stats { user: user })
)

(define-read-only (get-discovery-count)
  (var-get total-discoveries)
)

(define-read-only (get-discovery-counter)
  (var-get discovery-counter)
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

(define-read-only (is-paused)
  (var-get contract-paused)
)

;; Helper Functions
(define-private (update-user-stats (user principal) (reward-amount uint))
  (let 
    (
      (current-stats (default-to 
        { total-discoveries: u0, total-rewards: u0, last-discovery-time: u0 }
        (map-get? user-stats { user: user })
      ))
    )
    (map-set user-stats
      { user: user }
      {
        total-discoveries: (+ (get total-discoveries current-stats) u1),
        total-rewards: (+ (get total-rewards current-stats) reward-amount),
        last-discovery-time: block-height
      }
    )
  )
)

;; Emergency Functions
(define-public (emergency-mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-owner) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (< (+ (var-get total-supply) amount) MAX-SUPPLY) ERR-INVALID-AMOUNT)
    
    (mint-tokens amount recipient)
  )
)

;; Query all discovery types
(define-read-only (get-all-discovery-types)
  (list 
    { type: "new-species", multiplier: (get-discovery-multiplier "new-species") }
    { type: "mineral-deposit", multiplier: (get-discovery-multiplier "mineral-deposit") }
    { type: "hydrothermal-vent", multiplier: (get-discovery-multiplier "hydrothermal-vent") }
    { type: "underwater-formation", multiplier: (get-discovery-multiplier "underwater-formation") }
    { type: "archaeological-artifact", multiplier: (get-discovery-multiplier "archaeological-artifact") }
    { type: "rare-ecosystem", multiplier: (get-discovery-multiplier "rare-ecosystem") }
  )
)
