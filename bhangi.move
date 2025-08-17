module MyModule::TransparentQueue {
    use aptos_framework::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;

    /// Struct representing a queue reservation with token lock
    struct QueueReservation has store, key, drop {
        reserved_tokens: u64,     // Tokens locked for reservation
        reservation_time: u64,    // Timestamp when reservation was made
        penalty_rate: u64,        // Penalty percentage (0-100) for no-show
        is_active: bool,          // Whether the reservation is still active
    }

    /// Error codes
    const E_RESERVATION_EXISTS: u64 = 1;
    const E_NO_RESERVATION: u64 = 2;
    const E_INSUFFICIENT_TOKENS: u64 = 3;
    const E_RESERVATION_EXPIRED: u64 = 4;

    /// Function to create a queue reservation with token lock
    /// penalty_rate: percentage of tokens to forfeit if no-show (0-100)
    public fun reserve_queue_spot(
        user: &signer, 
        token_amount: u64, 
        penalty_rate: u64
    ) {
        let user_addr = signer::address_of(user);
        
        // Ensure user doesn't already have an active reservation
        assert!(!exists<QueueReservation>(user_addr), E_RESERVATION_EXISTS);
        
        // Lock tokens by withdrawing from user's account
        let locked_tokens = coin::withdraw<AptosCoin>(user, token_amount);
        coin::deposit<AptosCoin>(user_addr, locked_tokens);
        
        // Create reservation record
        let reservation = QueueReservation {
            reserved_tokens: token_amount,
            reservation_time: timestamp::now_seconds(),
            penalty_rate,
            is_active: true,
        };
        
        move_to(user, reservation);
    }

    /// Function to complete queue service or apply no-show penalty
    /// is_show: true if user showed up, false if no-show
    public fun complete_or_penalize(
        user: &signer,
        is_show: bool
    ) acquires QueueReservation {
        let user_addr = signer::address_of(user);
        
        // Ensure reservation exists
        assert!(exists<QueueReservation>(user_addr), E_NO_RESERVATION);
        
        let reservation = move_from<QueueReservation>(user_addr);
        let reserved_amount = reservation.reserved_tokens;
        let penalty_rate = reservation.penalty_rate;
        
        if (is_show) {
            // User showed up - return all tokens
            let refund = coin::withdraw<AptosCoin>(user, reserved_amount);
            coin::deposit<AptosCoin>(user_addr, refund);
        } else {
            // No-show penalty - forfeit percentage based on penalty_rate
            let penalty_amount = (reserved_amount * penalty_rate) / 100;
            let refund_amount = reserved_amount - penalty_amount;
            
            if (refund_amount > 0) {
                let partial_refund = coin::withdraw<AptosCoin>(user, refund_amount);
                coin::deposit<AptosCoin>(user_addr, partial_refund);
            }
            // Penalty tokens remain locked/burned (could be sent to treasury)
        };
    }
}