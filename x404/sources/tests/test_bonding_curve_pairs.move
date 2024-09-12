#[test_only]
module bonding_curve_launchpad::test_bonding_curve_pairs {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin as APT;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::genesis;
    use aptos_framework::managed_coin;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::primary_fungible_store::primary_store;
    use aptos_framework::randomness;
    use bonding_curve_launchpad::liquidity_pairs;
    use aptos_404::tokenized_nfts;
    use bonding_curve_launchpad::bonding_curve_launchpad;

    const ONE_FA_VALUE: u64 = 100_000_000;

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
    
    #[test(creator = @0xabcd)]
    fun test_create_fa_pair(creator: &signer) {
        setup_test();
        account::create_account_for_test(signer::address_of(creator));

        let aptos = account::create_account_for_test(@0x1);
        register_and_mint<APT>(&aptos, creator, 10 * 100_000_000);

        let descriptions = vector::empty<String>();
        vector::push_back(&mut descriptions, string::utf8(b"1st token"));
        vector::push_back(&mut descriptions, string::utf8(b"2nd token"));
        vector::push_back(&mut descriptions, string::utf8(b"3rd token"));

        let names = vector::empty<String>();
        vector::push_back(&mut names, string::utf8(b"token 1"));
        vector::push_back(&mut names, string::utf8(b"token 2"));
        vector::push_back(&mut names, string::utf8(b"token 3"));

        let uris = vector::empty<String>();
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token1"));
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token2"));
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token3"));

        let (_collection_address, _fa_metadata_address) = bonding_curve_launchpad::create_fa_pair_for_test(
            creator,
            5 * ONE_FA_VALUE,
            string::utf8(b"a Collection"),
            3,
            string::utf8(b"Collection A"),
            string::utf8(b"https://example.com/collection/a"),
            string::utf8(b"COA"),
            string::utf8(b"https://example.com/fa/a"),
            descriptions,
            names,
            uris
        );
    }

    #[test(swapper = @0xabcd)]
    fun test_create_fa_pair_and_swap(swapper: &signer) {
        let creator = &account::create_account_for_test(@0x1234);
        let swapper = &account::create_account_for_test(signer::address_of(swapper));
        setup_test();

        let aptos = account::create_account_for_test(@0x1);
        register_and_mint<APT>(&aptos, creator, 10 * 100_000_000);

        let descriptions = vector::empty<String>();
        vector::push_back(&mut descriptions, string::utf8(b"1st token"));
        vector::push_back(&mut descriptions, string::utf8(b"2nd token"));
        vector::push_back(&mut descriptions, string::utf8(b"3rd token"));

        let names = vector::empty<String>();
        vector::push_back(&mut names, string::utf8(b"token 1"));
        vector::push_back(&mut names, string::utf8(b"token 2"));
        vector::push_back(&mut names, string::utf8(b"token 3"));

        let uris = vector::empty<String>();
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token1"));
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token2"));
        vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token3"));

        // There's 50_000_000_000 fake APT and 300_000_000 fa in pool
        let (collection_address, fa_metadata_address) = bonding_curve_launchpad::create_fa_pair_for_test(
            creator,
            0,
            string::utf8(b"a Collection"),
            3,
            string::utf8(b"Collection A"),
            string::utf8(b"https://example.com/collection/a"),
            string::utf8(b"COA"),
            string::utf8(b"https://example.com/fa/a"),
            descriptions,
            names,
            uris
        );

        register_and_mint<APT>(&aptos, swapper, 250 * ONE_FA_VALUE);

        liquidity_pairs::swap_apt_to_fa(collection_address, swapper, object::address_to_object(fa_metadata_address), 250 * ONE_FA_VALUE);

        let fa_balance = primary_fungible_store::balance<fungible_asset::Metadata>(signer::address_of(swapper), object::address_to_object(fa_metadata_address));
        assert!(fa_balance == 1 * ONE_FA_VALUE, 1);

        let token_owned = tokenized_nfts::get_token_balance(object::address_to_object(collection_address), primary_store(signer::address_of(swapper), object::address_to_object<Metadata>(fa_metadata_address)));
        assert!(token_owned == 1, 2);
    }
}