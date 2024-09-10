#[test_only]
module aptos_404::tokenized_nfts_test {
    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::genesis;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store::{primary_store, ensure_primary_store_exists};
    use aptos_framework::randomness;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty::Royalty;
    use aptos_404::tokenized_nfts::{init_module_for_test, DispatchFunctionInfo, MetadataManager, FAManagedRef, HoldersInfo,
        create_collection_for_test, mint, get_fa_metadata_address_for_test,
        get_collection_404_metadata_for_test, get_collection_404_collection_for_test,
        get_token_balance, transfer, mint_for_test, commit_before_withdraw, commit_before_deposit,
    };

    const ONE_FA_VALUE: u64 = 100_000_000;
    use aptos_404::tokenized_nfts;

    fun setup_test() {
        genesis::setup();
        randomness::initialize_for_testing(&account::create_account_for_test(@0x1));
        init_module_for_test(&account::create_account_for_test(@aptos_404));
    }
    #[test(user = @0xabcd)]
    fun test_dispatch_withdraw_and_deposit(user: &signer) {
        setup_test();
        account::create_account_for_test(signer::address_of(user));
        let test = &account::create_account_for_test(@aptos_404);
        let collection_address = create_collection_for_test(
            user,
            string::utf8(b"a collection"),
            100,
            string::utf8(b"a name"),
            option::none<Royalty>(),
            string::utf8(b"https://example.com"),
            string::utf8(b"EX"),
            string::utf8(b"https://example.com/favicon.ico")
        );
        mint(
            user,
            collection_address,
            string::utf8(b"a token"),
            string::utf8(b"token"),
            string::utf8(b"https://example.com/token.png")
        );
        let metadata_address = get_fa_metadata_address_for_test(collection_address);
        let metadata = get_collection_404_metadata_for_test(metadata_address);
        let collection = get_collection_404_collection_for_test(metadata_address);
        let test_store = ensure_primary_store_exists(@aptos_404, metadata);
        let user_store = ensure_primary_store_exists(signer::address_of(user), metadata);
        assert!(get_token_balance(collection, test_store) == 1, 1);

        // let fa_transfer_ref = &borrow_global<Collection404TransferRef>(metadata_address).fa_transfer_ref;
        commit_before_withdraw(collection_address);
        commit_before_deposit(collection_address);
        let fa = dispatchable_fungible_asset::withdraw(test, test_store, ONE_FA_VALUE);
        dispatchable_fungible_asset::deposit(user_store, fa);

        // dispatchable_fungible_asset::transfer(test, test_store, user_store, ONE_FA_VALUE);
        // fungible_asset::transfer_with_ref(&collection404.fa_transfer_ref, test_store, user_store, ONE_FA_VALUE);

        assert!(get_token_balance(collection, test_store) == 0, 1);
        assert!(get_token_balance(collection, user_store) == 1, 1);
    }

    #[test(user = @0xabcd)]
    fun test_transfer_404(user: &signer) {
        setup_test();
        account::create_account_for_test(signer::address_of(user));
        let test = &account::create_account_for_test(@aptos_404);
        let collection_address = create_collection_for_test(
            user,
            string::utf8(b"a collection"),
            100,
            string::utf8(b"a name"),
            option::none<Royalty>(),
            string::utf8(b"https://example.com"),
            string::utf8(b"EX"),
            string::utf8(b"https://example.com/favicon.ico")
        );
        let token_address = mint_for_test(
            user,
            collection_address,
            string::utf8(b"a token"),
            string::utf8(b"token"),
            string::utf8(b"https://example.com/token.png")
        );
        let metadata_address = get_fa_metadata_address_for_test(collection_address);
        let metadata = get_collection_404_metadata_for_test(metadata_address);
        let collection = get_collection_404_collection_for_test(metadata_address);
        let test_store = ensure_primary_store_exists(@aptos_404, metadata);
        let user_store = ensure_primary_store_exists(signer::address_of(user), metadata);
        assert!(get_token_balance(collection, test_store) == 1, 1);
        std::debug::print(&string::utf8(b"token address"));
        std::debug::print(&token_address);
        transfer(test, signer::address_of(user), token_address);

        assert!(get_token_balance(collection, test_store) == 0, 1);
        assert!(get_token_balance(collection, user_store) == 1, 1);
    }
}
