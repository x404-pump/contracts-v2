#[test_only]
module bonding_curve_launchpad::test_liquidity_pairs {
    use std::signer;
    use aptos_framework::aptos_coin::AptosCoin as APT;
    use aptos_framework::account;
    use aptos_framework::genesis;
    use aptos_framework::managed_coin;
    use aptos_framework::randomness;
    use aptos_404::tokenized_nfts;
    use bonding_curve_launchpad::liquidity_pairs;

    const ONE_FA_VALUE: u64 = 100_000_000;
    const INITIAL_VIRTUAL_FA_LIQUIDITY: u128 = 50_00_000_000;

    fun register_and_mint<CoinType>(account: &signer, to: &signer, amount: u64) {
        managed_coin::register<CoinType>(to);
        managed_coin::mint<CoinType>(account, signer::address_of(to), amount);
    }

    fun setup_test() {
        genesis::setup();
        let aptos = account::create_account_for_test(@0x1);
        randomness::initialize_for_testing(&aptos);
        tokenized_nfts::init_module_for_test(&account::create_account_for_test(@aptos_404));

        managed_coin::initialize<APT>(
            &aptos,
            b"Aptos",
            b"APT",
            8,
            false,
        );
    }

    //---------------------------View Tests---------------------------
    #[test(deployer = @bonding_curve_launchpad)]
    #[expected_failure(abort_code = liquidity_pairs::ELIQUIDITY_PAIR_SWAP_AMOUNTOUT_INSIGNIFICANT, location = liquidity_pairs)]
    public fun test_insignificant_fa_swap(deployer: &signer) {
        liquidity_pairs::initialize_for_test(deployer);
        liquidity_pairs::get_amount_out(1_000_000_000 + INITIAL_VIRTUAL_FA_LIQUIDITY, 2_000_000_000, true, 0, 1_000_000_000);
    }

    #[test(deployer = @bonding_curve_launchpad)]
    #[expected_failure(abort_code = liquidity_pairs::ELIQUIDITY_PAIR_SWAP_AMOUNTOUT_INSIGNIFICANT, location = liquidity_pairs)]
    public fun test_insignificant_apt_swap(deployer: &signer) {
        liquidity_pairs::initialize_for_test(deployer);
        liquidity_pairs::get_amount_out(1_000_000_000 + INITIAL_VIRTUAL_FA_LIQUIDITY, 2_000_000_000, false, 0, 1_000_000_000);
    }

    #[test(deployer = @bonding_curve_launchpad)]
    public fun test_get_amount_out(deployer: &signer) {
        liquidity_pairs::initialize_for_test(deployer);
        let (fa_gained, amount_in, fa_updated_reserves, apt_updated_reserves) = liquidity_pairs::get_amount_out(300_000_000 + INITIAL_VIRTUAL_FA_LIQUIDITY, 600_000_000, false, 300_000_000, 300_000_000);
        assert!(fa_gained == 300_000_000, 1);

        let (amount_in, apt_gained, fa_updated_reserves, apt_updated_reserves) = liquidity_pairs::get_amount_out(300_000_000 + INITIAL_VIRTUAL_FA_LIQUIDITY, 600_000_000, true, 300_000_000, 300_000_000);
        assert!(apt_gained == 32_142_857, 2);
    }
}
