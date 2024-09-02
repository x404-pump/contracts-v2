module test::test {
  use std::signer;
  use std::string::{Self, String};
  use std::option::{Self, Option};
  use std::vector::{Self};
  use aptos_std::math128::{Self};
  use aptos_framework::object::{Self, Object, TransferRef};
  use aptos_framework::primary_fungible_store::{Self};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, TransferRef as FungibleTransferRef, MintRef};
  use aptos_token_objects::collection::{Self, Collection};
  use aptos_token_objects::token::{Self};
  use aptos_token_objects::royalty::{Self, Royalty};
  use aptos_framework::function_info::{Self, FunctionInfo};
  use aptos_framework::dispatchable_fungible_asset::{Self};

  #[test_only]
  use aptos_framework::account;
  #[test_only]
  use aptos_framework::genesis::setup;

  use aptos_std::smart_vector::{Self, SmartVector};
  #[test_only]
  use aptos_framework::genesis;
  #[test_only]
  use aptos_framework::primary_fungible_store::{primary_store, ensure_primary_store_exists};
  #[test_only]
  use aptos_framework::randomness;

  const DECIMALs: u8 = 8;
  const ONE_FA_VALUE: u64 = 100_000_000;

  struct Token404 has key {
    collection: Object<Collection>,
    transfer_ref: TransferRef,
  }

  struct Collection404 has key {
    collection: Object<Collection>,
    mint_ref: MintRef,
  }

  struct Collection404TransferRef has key {
    fa_transfer_ref: FungibleTransferRef
  }

  struct TokenFunctionInfo has key {
    deposit_override: FunctionInfo,
    withdraw_override: FunctionInfo,
  }

  struct OwnerInfo has key, store, copy {
    owner: address, 
    token: Object<Token404>,
  }

  struct Token404Info has key {
    holders: SmartVector<OwnerInfo>,
  }


  fun init_module(account_signer: &signer) {
    let deposit_override = function_info::new_function_info(
      account_signer, 
      string::utf8(b"test"), 
      string::utf8(b"deposit")
    );
    let withdraw_override = function_info::new_function_info(
      account_signer, 
      string::utf8(b"test"), 
      string::utf8(b"withdraw")
    );
    let token_function_info = TokenFunctionInfo {
      deposit_override: deposit_override,
      withdraw_override: withdraw_override,
    };
    move_to(account_signer, token_function_info);
  }

  #[view]
  public fun get_fa_metadata_seed(fa_name: String): String {
    let seed = string::utf8(b"x404-fa-metadata");
    string::append(&mut seed, fa_name);
    seed
  }

  #[view]
  public fun get_collection_seed(collection_namme: String): String {
    let seed = string::utf8(b"x404-collection");
    string::append(&mut seed, collection_namme);
    seed
  }

  #[view]
  public fun get_nfts_seed(token_name: String): String {
    let seed = string::utf8(b"x404-token");
    string::append(&mut seed, token_name);
    seed
  }

  #[view]
  fun get_fa_metadata_address(collection_address: address): address {
    let collection_object = object::address_to_object<Collection>(collection_address);
    let creator = collection::creator<Collection>(collection_object);
    let name = collection::name<Collection>(collection_object);
    let metadata_seed = get_fa_metadata_seed(name);
    object::create_object_address(&creator, *string::bytes(&metadata_seed))
  }

  #[lint::allow_unsafe_randomness]  
  public fun withdraw<T: key>(
    store: Object<T>,
    amount: u64,
    transfer_ref: &FungibleTransferRef,
  ): FungibleAsset acquires Collection404, Token404Info, Token404 {
    let metadata = fungible_asset::store_metadata<T>(store);
    let balance_before = fungible_asset::balance<T>(store);
    let owner = object::owner<T>(store);
    let fa = fungible_asset::withdraw_with_ref<T>(
      transfer_ref,
      store,
      amount,
    );
    let balance_after = fungible_asset::balance<T>(store);
    let amount_nft_withdrawn = balance_before / ONE_FA_VALUE - balance_after / ONE_FA_VALUE;
    
    let collection = borrow_global<Collection404>(object::object_address(&metadata)).collection;
    let index_vector = smart_vector::new<u64>();
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders, i);
      if (holder.owner == owner) {
        smart_vector::push_back(&mut index_vector, i);
      }
    };
    for (i in 0..amount_nft_withdrawn) {
      let index = aptos_framework::randomness::u64_range(0, smart_vector::length<u64>(&index_vector));
      let holder_index = smart_vector::remove<u64>(&mut index_vector, index);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<Token404Info>(object::object_address(&collection)).holders, holder_index);
      let nft = holder.token;
      let token404 = borrow_global<Token404>(object::object_address(&nft));
      let nft_linear_transfer_ref = object::generate_linear_transfer_ref(&token404.transfer_ref);
      object::transfer_with_ref(nft_linear_transfer_ref, @test);
      holder.owner = @test;
    };
    smart_vector::destroy<u64>(index_vector);

    fa
  }

  #[lint::allow_unsafe_randomness]
  public fun deposit<T: key>(
    store: Object<T>,
    fa: FungibleAsset,
    transfer_ref: &FungibleTransferRef,
  ) acquires Collection404, Token404Info, Token404 {
    let metadata = fungible_asset::store_metadata<T>(store);
    let balance_before = fungible_asset::balance<T>(store);
    let owner = object::owner<T>(store);
    fungible_asset::deposit_with_ref<T>(
      transfer_ref,
      store,
      fa,
    );
    let balance_after = fungible_asset::balance<T>(store);
    let amount_nft_deposited = balance_after / ONE_FA_VALUE - balance_before / ONE_FA_VALUE;
    let collection = borrow_global<Collection404>(object::object_address(&metadata)).collection;
    let index_vector = smart_vector::new<u64>();
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders, i);
      if (holder.owner == @test) {
        smart_vector::push_back(&mut index_vector, i);
      }
    };
    for (i in 0..amount_nft_deposited) {
      let index = aptos_framework::randomness::u64_range(0, smart_vector::length<u64>(&index_vector));
      let holder_index = smart_vector::remove<u64>(&mut index_vector, index);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<Token404Info>(object::object_address(&collection)).holders, holder_index);
      let nft = holder.token;
      let token404 = borrow_global<Token404>(object::object_address(&nft));
      let nft_linear_transfer_ref = object::generate_linear_transfer_ref(&token404.transfer_ref);
      object::transfer_with_ref(nft_linear_transfer_ref, owner);
      holder.owner = owner;
    };
    smart_vector::destroy<u64>(index_vector);
  }

  // fun get_collection_address(creator: address, collection_name: String): address {
  //   let collection_seed = get_collection_seed(collection_name);
  //   let collection_address = object::create_object_address(&creator, *string::bytes(&collection_seed));
  //   collection_address
  // }

  // fun get_collection_address_from_fa_metadata(fa_metadata_address: address): address {
  //   let metadata_object = object::address_to_object<Metadata>(fa_metadata_address);
  //   let fa_name = fungible_asset::name<Metadata>(metadata_object);
  //   // get_collection_address(&signer::address_of(&signer::get()), fa_name)
  // }

  fun create_collection_interal(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String): address acquires TokenFunctionInfo {

    assert!(supply > 0 && supply <= 1_000_000, 101);

    let collection_constructor_ref = collection::create_fixed_collection(
      creator, description, supply, name, royalty, uri);

    let metadata_seed = get_fa_metadata_seed(name);
    let metadata_object_constructor_ref = object::create_named_object(creator, *string::bytes(&metadata_seed));
    let fa_supply = supply * ONE_FA_VALUE;
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      &metadata_object_constructor_ref,
      option::some((fa_supply as u128)),
      name, /* name */
      fa_symbol, /* symbol */
      DECIMALs, /* decimals */
      fa_icon, /* icon */
      uri, /* project */
    );
    let mint_ref = fungible_asset::generate_mint_ref(&metadata_object_constructor_ref);
    let fa_transfer_ref = fungible_asset::generate_transfer_ref(&metadata_object_constructor_ref);
    let function_override = borrow_global<TokenFunctionInfo>(@test);
    dispatchable_fungible_asset::register_dispatch_functions(
      &metadata_object_constructor_ref,
      option::some(function_override.withdraw_override),
      option::some(function_override.deposit_override),
      option::none(),
    );

    // store collection info in metadata
    let metadata_signer = object::generate_signer(&metadata_object_constructor_ref);
    move_to(&metadata_signer, Collection404 {
      collection: object::object_from_constructor_ref<Collection>(&collection_constructor_ref),
      mint_ref,
    });
    move_to(&metadata_signer, Collection404TransferRef {
      fa_transfer_ref
    });
    // store nft owners info
    let collection_signer = object::generate_signer(&collection_constructor_ref);
    move_to(&collection_signer, Token404Info {
      holders: smart_vector::new<OwnerInfo>(),
    });
    object::address_from_constructor_ref(&collection_constructor_ref)
  }

  entry public fun create_collection(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String) acquires TokenFunctionInfo {
    create_collection_interal(creator, description, supply, name, royalty, uri, fa_symbol, fa_icon);
  } 

  entry public fun mint_404_in_collection(creator: &signer, collection_address: address, description: String, name: String, uri: String)
  acquires Token404Info, Collection404, Token404 {
    let collection_object = object::address_to_object<Collection>(collection_address);
    let nft_constructor_ref = token::create_named_token_object(
      creator,
      collection_object,
      description,
      name,
      option::none(),
      uri
    );
    let nft_signer = object::generate_signer(&nft_constructor_ref);
    let nft_transfer_ref = object::generate_transfer_ref(&nft_constructor_ref);
    move_to(&nft_signer, Token404 {
      collection: collection_object,
      transfer_ref: nft_transfer_ref,
    });
    let nft_transfer_ref = &borrow_global<Token404>(signer::address_of(&nft_signer)).transfer_ref;
    let nft_object = object::object_from_constructor_ref<Token404>(&nft_constructor_ref);
    object::transfer<Token404>(creator, nft_object, @test);
    object::disable_ungated_transfer(nft_transfer_ref);
    smart_vector::push_back(&mut borrow_global_mut<Token404Info>(collection_address).holders, OwnerInfo {
      owner: @test,
      token: nft_object,
    });
    let metadata_address = get_fa_metadata_address(collection_address);
    primary_fungible_store::mint(&borrow_global<Collection404>(metadata_address).mint_ref, @test, ONE_FA_VALUE);
  }

  entry public fun mint_batch_404s_in_collection(creator: &signer, collection_address: address, descriptions: vector<String>, names: vector<String>, uris: vector<String>)
  acquires Token404Info, Collection404, Token404 {
    assert!(vector::length<String>(&descriptions) == vector::length<String>(&names) && vector::length<String>(&names) == vector::length<String>(&uris), 101);
    let collection_object = object::address_to_object<Collection>(collection_address);
    for (i in 0..vector::length<String>(&descriptions)) {
      mint_404_in_collection(creator, collection_address, *vector::borrow<String>(&descriptions, i), *vector::borrow<String>(&names, i), *vector::borrow<String>(&uris, i));
    };
  }

  entry public fun transfer_404(from: &signer, to: address, token_address: address) acquires Token404 {
    let token_object = object::address_to_object<Token404>(token_address);
    let collection_object = token::collection_object<Token404>(token_object);
    // if (collection::count)
    let token404 = borrow_global<Token404>(token_address);
    object::enable_ungated_transfer(&token404.transfer_ref);
    object::transfer<Token404>(from, token_object, to);
    object::disable_ungated_transfer(&token404.transfer_ref);
  }

  #[test_only]
  fun setup_test() {
    genesis::setup();
    randomness::initialize_for_testing(&account::create_account_for_test(@0x1));
    init_module(&account::create_account_for_test(@test));
  }

  #[test_only]
  fun get_token_owns<T: key>(collection: Object<Collection>, store: Object<T>): u64 acquires Token404Info {
    let metadata = fungible_asset::store_metadata<T>(store);
    let owner = object::owner<T>(store);
    // let collection = borrow_global<Collection404>(object::object_address(&metadata)).collection;
    let token_owns: u64 = 0;
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<Token404Info>(object::object_address(&collection)).holders, i);
      if (holder.owner == owner) {
        token_owns = token_owns + 1;
      }
    };
    token_owns
  }
  #[test(user = @0xabcd)]
  fun test_withdraw_and_deposit(user: &signer) acquires TokenFunctionInfo, Token404Info, Collection404, Token404, Collection404TransferRef {
    setup_test();
    account::create_account_for_test(signer::address_of(user));
    let test = &account::create_account_for_test(@test);
    let collection_address = create_collection_interal(
      user,
      string::utf8(b"a collection"),
      100,
      string::utf8(b"a name"),
      option::none<Royalty>(),
      string::utf8(b"https://example.com"),
      string::utf8(b"EX"),
      string::utf8(b"https://example.com/favicon.ico")
    );
    mint_404_in_collection(
      user,
      collection_address,
      string::utf8(b"a token"),
      string::utf8(b"token"),
      string::utf8(b"https://example.com/token.png")
    );
    let metadata_address = get_fa_metadata_address(collection_address);
    let collection404 = borrow_global<Collection404>(metadata_address);
    let metadata = fungible_asset::mint_ref_metadata(&collection404.mint_ref);
    let collection = collection404.collection;
    let test_store = ensure_primary_store_exists(@test, metadata);
    let user_store = ensure_primary_store_exists(signer::address_of(user), metadata);
    assert!(get_token_owns(collection, test_store) == 1, 1);

    let fa_transfer_ref = &borrow_global<Collection404TransferRef>(metadata_address).fa_transfer_ref;
    let fa = withdraw(test_store, ONE_FA_VALUE, fa_transfer_ref);
    deposit(user_store, fa, fa_transfer_ref);
    // fungible_asset::transfer_with_ref(&collection404.fa_transfer_ref, test_store, user_store, ONE_FA_VALUE);

    assert!(get_token_owns(collection, test_store) == 0, 1);
    assert!(get_token_owns(collection, user_store) == 1, 1);
  }
}