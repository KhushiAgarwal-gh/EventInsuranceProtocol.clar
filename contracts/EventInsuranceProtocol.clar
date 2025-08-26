;; EventInsurance Protocol
;; A decentralized event cancellation insurance system with weather triggers
;; and automated compensation mechanism

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-policy-not-found (err u102))
(define-constant err-event-not-cancelled (err u103))
(define-constant err-already-claimed (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-invalid-weather-trigger (err u106))

;; Weather trigger types
(define-constant WEATHER-RAIN u1)
(define-constant WEATHER-STORM u2)
(define-constant WEATHER-EXTREME-TEMP u3)

;; Data structures
(define-map insurance-policies
  uint  ;; policy-id
  {
    event-organizer: principal,
    event-date: uint,
    premium-paid: uint,
    coverage-amount: uint,
    weather-trigger: uint,
    is-active: bool,
    is-claimed: bool
  }
)

(define-map weather-data
  uint  ;; date (block height or timestamp)
  {
    condition: uint,  ;; weather condition code
    severity: uint,   ;; severity level (1-10)
    reported-by: principal
  }
)

;; State variables
(define-data-var policy-counter uint u0)
(define-data-var total-premiums-collected uint u0)
(define-data-var total-claims-paid uint u0)

;; Function 1: Create Insurance Policy
;; Allows event organizers to purchase insurance coverage for their events
(define-public (create-insurance-policy 
  (event-date uint) 
  (coverage-amount uint) 
  (weather-trigger uint))
  (let 
    (
      (policy-id (+ (var-get policy-counter) u1))
      (premium (/ coverage-amount u10))  ;; Premium is 10% of coverage amount
    )
    ;; Validation checks
    (asserts! (> coverage-amount u0) err-invalid-amount)
    (asserts! (> event-date stacks-block-height) err-invalid-amount)
    (asserts! (or (is-eq weather-trigger WEATHER-RAIN)
                  (or (is-eq weather-trigger WEATHER-STORM)
                      (is-eq weather-trigger WEATHER-EXTREME-TEMP))) 
              err-invalid-weather-trigger)
    
    ;; Transfer premium from event organizer to contract
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    ;; Create the insurance policy
    (map-set insurance-policies policy-id
      {
        event-organizer: tx-sender,
        event-date: event-date,
        premium-paid: premium,
        coverage-amount: coverage-amount,
        weather-trigger: weather-trigger,
        is-active: true,
        is-claimed: false
      }
    )
    
    ;; Update state variables
    (var-set policy-counter policy-id)
    (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium))
    
    ;; Emit event log
    (print {
      action: "policy-created",
      policy-id: policy-id,
      organizer: tx-sender,
      coverage: coverage-amount,
      premium: premium
    })
    
    (ok policy-id)
  )
)

;; Function 2: Claim Insurance Compensation
;; Allows policy holders to claim compensation when weather conditions trigger cancellation
(define-public (claim-compensation (policy-id uint) (weather-date uint))
  (let
    (
      (policy (unwrap! (map-get? insurance-policies policy-id) err-policy-not-found))
      (weather (unwrap! (map-get? weather-data weather-date) err-event-not-cancelled))
    )
    ;; Validation checks
    (asserts! (is-eq tx-sender (get event-organizer policy)) err-owner-only)
    (asserts! (get is-active policy) err-policy-not-found)
    (asserts! (not (get is-claimed policy)) err-already-claimed)
    
    ;; Check if weather condition matches the trigger and is severe enough
    (asserts! (is-eq (get condition weather) (get weather-trigger policy)) err-event-not-cancelled)
    (asserts! (>= (get severity weather) u7) err-event-not-cancelled)  ;; Severity threshold
    
    ;; Check if weather occurred on or near event date (within 1 day)
    (asserts! (<= (- (get event-date policy) weather-date) u144) err-event-not-cancelled)  ;; 144 blocks  1 day
    
    ;; Ensure contract has sufficient funds
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) (get coverage-amount policy)) 
              err-insufficient-funds)
    
    ;; Transfer compensation to the policy holder
    (try! (as-contract (stx-transfer? (get coverage-amount policy) tx-sender (get event-organizer policy))))
    
    ;; Update policy status
    (map-set insurance-policies policy-id
      (merge policy { is-claimed: true, is-active: false })
    ) 
    
    ;; Update total claims paid
    (var-set total-claims-paid (+ (var-get total-claims-paid) (get coverage-amount policy)))
    
    ;; Emit event log
    (print {
      action: "compensation-claimed",
      policy-id: policy-id,
      organizer: (get event-organizer policy),
      amount: (get coverage-amount policy),
      weather-condition: (get condition weather)
    })
    
    (ok (get coverage-amount policy))
  )
)

;; Read-only functions for querying data
(define-read-only (get-policy (policy-id uint))
  (map-get? insurance-policies policy-id)
)

(define-read-only (get-weather-data (date uint))
  (map-get? weather-data date)
)

(define-read-only (get-contract-stats)
  {
    total-policies: (var-get policy-counter),
    total-premiums: (var-get total-premiums-collected),
    total-claims: (var-get total-claims-paid),
    contract-balance: (stx-get-balance (as-contract tx-sender))
  }
)

;; Oracle function to report weather data (restricted to authorized oracles)
(define-public (report-weather (date uint) (condition uint) (severity uint))
  (begin
    ;; In production, this should be restricted to authorized weather oracles
    (map-set weather-data date
      {
        condition: condition,
        severity: severity,
        reported-by: tx-sender
      }
    )
    (ok true)
  )
)