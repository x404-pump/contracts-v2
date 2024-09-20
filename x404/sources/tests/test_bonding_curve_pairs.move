#[test_only]
module bonding_curve_launchpad::test_bonding_curve_pairs {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_std::string_utils;
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
    use aptos_404::tokenized_nfts;
    use bonding_curve_launchpad::liquidity_pairs;
    use bonding_curve_launchpad::bonding_curve_launchpad;
    use swap::router;

    const ONE_FA_VALUE: u64 = 100_000_000;

    fun register_and_mint<CoinType>(account: &signer, to: &signer, amount: u64) {
        managed_coin::register<CoinType>(to);
        managed_coin::mint<CoinType>(account, signer::address_of(to), amount);
    }

    fun setup_test() {
        genesis::setup();
        swap::package_manager::initialize_for_test(&account::create_account_for_test(@deployer));
        swap::coin_wrapper::initialize();
        swap::liquidity_pool::initialize();
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
        register_and_mint<APT>(&aptos, creator, 1000000 * 100_000_000);

        let descriptions = vector::empty<String>();
        let names = vector::empty<String>();
        let uris = vector::empty<String>();

        for (i in 0..1000) {
            let token_name = string_utils::to_string_with_integer_types<u64>(&i);
            vector::push_back(&mut descriptions, token_name);
            vector::push_back(&mut names, token_name);
            vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token"));
        };

        let (_collection_address, fa_metadata_address) = bonding_curve_launchpad::create_fa_pair_for_test(
            creator,
            258 * 100_000_000,
            string::utf8(b"a Collection"),
            1000,
            string::utf8(b"Collection A"),
            string::utf8(b"https://example.com/collection/a"),
            string::utf8(b"COA"),
            string::utf8(b"https://example.com/fa/a"),
            descriptions,
            names,
            uris,
            100_000_000
        );

        let fa_balance = primary_fungible_store::balance<fungible_asset::Metadata>(signer::address_of(creator), object::address_to_object(fa_metadata_address));
        assert!(fa_balance == 20508744038, 1);
    }

    #[test(swapper = @0xabcd)]
    fun test_create_fa_pair_and_swap(swapper: &signer) {
        let creator = &account::create_account_for_test(@0x1234);
        let swapper = &account::create_account_for_test(signer::address_of(swapper));
        setup_test();

        let aptos = account::create_account_for_test(@0x1);
        register_and_mint<APT>(&aptos, creator, 1 * 100_000_000);

        let descriptions = vector::empty<String>();
        let names = vector::empty<String>();
        let uris = vector::empty<String>();

        let token_supply = 1000;

        for (i in 0..token_supply) {
            let token_name = string_utils::to_string_with_integer_types<u64>(&i);
            vector::push_back(&mut descriptions, token_name);
            vector::push_back(&mut names, token_name);
            vector::push_back(&mut uris, string::utf8(b"https://example.com/collection/a/token"));
        };

        let (collection_address, fa_metadata_address) = bonding_curve_launchpad::create_fa_pair_for_test(
            creator,
            0,
            string::utf8(b"a Collection"),
            token_supply,
            string::utf8(b"Collection A"),
            string::utf8(b"https://example.com/collection/a"),
            string::utf8(b"COA"),
            string::utf8(b"https://example.com/fa/a"),
            descriptions,
            names,
            uris,
            100_000_000
        );

        let mint_amount = 10000 * ONE_FA_VALUE;
        let swap_amount = 2000 * ONE_FA_VALUE;

        register_and_mint<APT>(&aptos, swapper, mint_amount);

        liquidity_pairs::swap_apt_to_fa(collection_address, swapper, object::address_to_object(fa_metadata_address), swap_amount);

        let fa_balance = primary_fungible_store::balance<fungible_asset::Metadata>(signer::address_of(swapper), object::address_to_object(fa_metadata_address));
        assert!(fa_balance == 50000000000, 1);

        let token_owned = tokenized_nfts::get_token_balance(object::address_to_object(collection_address), primary_store(signer::address_of(swapper), object::address_to_object<Metadata>(fa_metadata_address)));
        assert!(token_owned == 500, 2);

        router::swap_coin_for_asset_public<APT>(
            swapper,
            500 * ONE_FA_VALUE,
            0,
            object::address_to_object(fa_metadata_address),
            false,
            signer::address_of(swapper),
        );
        token_owned = tokenized_nfts::get_token_balance(object::address_to_object(collection_address), primary_store(signer::address_of(swapper), object::address_to_object<Metadata>(fa_metadata_address)));    
        assert!(token_owned == 500 + 249, 3);
        
        fa_balance = primary_fungible_store::balance<fungible_asset::Metadata>(signer::address_of(swapper), object::address_to_object(fa_metadata_address));
        assert!(fa_balance == 24974974974 + 50000000000, 4);
    }
}
