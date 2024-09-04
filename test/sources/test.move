module test::test {
  use std::signer;
  use std::string::{Self, String};
  use std::option::{Self, Option};
  use std::vector::{Self};
  use aptos_std::smart_vector::{Self, SmartVector};
  use aptos_framework::object::{Self, Object, TransferRef};
  use aptos_framework::primary_fungible_store::{Self};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, TransferRef as FungibleTransferRef, MintRef};
  use aptos_token_objects::collection::{Self, Collection};
  use aptos_token_objects::token::{Self, Token};
  use aptos_token_objects::royalty::{Self, Royalty};
  use aptos_framework::function_info::{Self, FunctionInfo};
  use aptos_framework::dispatchable_fungible_asset::{Self};

  const DECIMALs: u8 = 8;
  const ONE_FA_VALUE: u64 = 100_000_000;

  struct TokenManager has key {
    collection: Object<Collection>,
    transfer_ref: TransferRef,
  }

  // store in metadata
  struct MetadataManager has key {
    collection: Object<Collection>,
    mint_ref: MintRef,
  }

  struct FAManagedRef has key {
    fa_transfer_ref: FungibleTransferRef
  }

  struct DispatchFunctionInfo has key {
    deposit_override: FunctionInfo,
    withdraw_override: FunctionInfo,
  }

  struct OwnerInfo has key, store, copy, drop {
    owner: address, 
    token: Object<TokenManager>,
  }

  struct HoldersInfo has key {
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
    let token_function_info = DispatchFunctionInfo {
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
  ): FungibleAsset acquires MetadataManager, HoldersInfo, TokenManager {
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

    let collection = borrow_global<MetadataManager>(object::object_address(&metadata)).collection;
    let index_vector = smart_vector::new<u64>();
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders, i);
      if (holder.owner == owner) {
        smart_vector::push_back(&mut index_vector, i);
      }
    };
    for (i in 0..amount_nft_withdrawn) {
      let index = aptos_framework::randomness::u64_range(0, smart_vector::length<u64>(&index_vector));
      let holder_index = smart_vector::remove<u64>(&mut index_vector, index);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(object::object_address(&collection)).holders, holder_index);
      let nft = holder.token;
      let token404 = borrow_global<TokenManager>(object::object_address(&nft));
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
  ) acquires TokenManager, HoldersInfo, MetadataManager {
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
    let collection = borrow_global<MetadataManager>(object::object_address(&metadata)).collection;
    let index_vector = smart_vector::new<u64>();
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders, i);
      if (holder.owner == @test) {
        smart_vector::push_back(&mut index_vector, i);
      }
    };
    for (i in 0..amount_nft_deposited) {
      let index = aptos_framework::randomness::u64_range(0, smart_vector::length<u64>(&index_vector));
      let holder_index = smart_vector::remove<u64>(&mut index_vector, index);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(object::object_address(&collection)).holders, holder_index);
      let nft = holder.token;
      let token404 = borrow_global<TokenManager>(object::object_address(&nft));
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

  fun create_collection_internal(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String): address acquires DispatchFunctionInfo {

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
    let function_override = borrow_global<DispatchFunctionInfo>(@test);
    dispatchable_fungible_asset::register_dispatch_functions(
      &metadata_object_constructor_ref,
      option::some(function_override.withdraw_override),
      option::some(function_override.deposit_override),
      option::none(),
    );

    // store collection info in metadata
    let metadata_signer = object::generate_signer(&metadata_object_constructor_ref);
    move_to(&metadata_signer, MetadataManager {
      collection: object::object_from_constructor_ref<Collection>(&collection_constructor_ref),
      mint_ref,
    });
    move_to(&metadata_signer, FAManagedRef {
      fa_transfer_ref
    });
    // store nft owners info
    let collection_signer = object::generate_signer(&collection_constructor_ref);
    move_to(&collection_signer, HoldersInfo {
      holders: smart_vector::new<OwnerInfo>(),
    });
    object::address_from_constructor_ref(&collection_constructor_ref)
  }

  entry public fun create_collection(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String) acquires DispatchFunctionInfo {
    create_collection_internal(creator, description, supply, name, royalty, uri, fa_symbol, fa_icon);
  }

  fun mint_internal(creator: &signer, collection_address: address, description: String, name: String, uri: String) : address
  acquires TokenManager, MetadataManager, HoldersInfo {
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
    move_to(&nft_signer, TokenManager {
      collection: collection_object,
      transfer_ref: nft_transfer_ref,
    });
    let nft_transfer_ref = &borrow_global<TokenManager>(signer::address_of(&nft_signer)).transfer_ref;
    let nft_object = object::object_from_constructor_ref<TokenManager>(&nft_constructor_ref);
    object::transfer<TokenManager>(creator, nft_object, @test);
    object::disable_ungated_transfer(nft_transfer_ref);
    smart_vector::push_back(&mut borrow_global_mut<HoldersInfo>(collection_address).holders, OwnerInfo {
      owner: @test,
      token: nft_object,
    });
    let metadata_address = get_fa_metadata_address(collection_address);
    primary_fungible_store::mint(&borrow_global<MetadataManager>(metadata_address).mint_ref, @test, ONE_FA_VALUE);
    signer::address_of(&nft_signer)
  }

  entry public fun mint(creator: &signer, collection_address: address, description: String, name: String, uri: String)
  acquires TokenManager, MetadataManager, HoldersInfo {
    mint_internal(creator, collection_address, description, name, uri);
  }

  entry public fun mint_batch_404s_in_collection(creator: &signer, collection_address: address, descriptions: vector<String>, names: vector<String>, uris: vector<String>)
  acquires TokenManager, MetadataManager, HoldersInfo {
    assert!(vector::length<String>(&descriptions) == vector::length<String>(&names) && vector::length<String>(&names) == vector::length<String>(&uris), 101);
    let collection_object = object::address_to_object<Collection>(collection_address);
    for (i in 0..vector::length<String>(&descriptions)) {
      mint(creator, collection_address, *vector::borrow<String>(&descriptions, i), *vector::borrow<String>(&names, i), *vector::borrow<String>(&uris, i));
    };
  }

  entry public fun transfer(from: &signer, to: address, token_address: address) acquires TokenManager, FAManagedRef, HoldersInfo {
    assert!(signer::address_of(from) != to, 101); 
    let token_object = object::address_to_object<TokenManager>(token_address);
    let collection_object = token::collection_object<TokenManager>(token_object);
    let token404 = borrow_global<TokenManager>(token_address);
    let nft_linear_transfer_ref = object::generate_linear_transfer_ref(&token404.transfer_ref);
    object::transfer_with_ref(nft_linear_transfer_ref, to);
    // object::enable_ungated_transfer(&token404.transfer_ref);
    // object::transfer<Token404>(from, token_object, to);
    // object::disable_ungated_transfer(&token404.transfer_ref);
    let (flag, index) = smart_vector::index_of<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection_object)).holders, &OwnerInfo {
      owner: signer::address_of(from),
      token: token_object,
    });
    assert!(flag == true, 101);
    let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(object::object_address(&collection_object)).holders, index);
    holder.owner = to;
    let metadata_address = get_fa_metadata_address(object::object_address(&collection_object));
    let metadata_object = object::address_to_object<Metadata>(metadata_address);
    let from_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(from), metadata_object);
    let to_store = primary_fungible_store::ensure_primary_store_exists(to, metadata_object);
    let fa_transfer_ref = &borrow_global<FAManagedRef>(metadata_address).fa_transfer_ref;
    let fa_from = fungible_asset::withdraw_with_ref(fa_transfer_ref, from_store, ONE_FA_VALUE);
    fungible_asset::deposit_with_ref(fa_transfer_ref, to_store, fa_from);
  }

  #[test_only]
  public fun init_module_for_test(account_signer: &signer) {
    init_module(account_signer);
  }

  #[test_only]
  public fun create_collection_for_test(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String): address acquires DispatchFunctionInfo {
    create_collection_internal(creator, description, supply, name, royalty, uri, fa_symbol, fa_icon)
  }

  #[test_only]
  public fun get_token_balance<T: key>(collection: Object<Collection>, store: Object<T>): u64 acquires HoldersInfo {
    // let metadata = fungible_asset::store_metadata<T>(store);
    let owner = object::owner<T>(store);
    // let collection = borrow_global<Collection404>(object::object_address(&metadata)).collection;
    let balance: u64 = 0;
    for (i in 0..smart_vector::length<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders)) {
      let holder = smart_vector::borrow<OwnerInfo>(&borrow_global<HoldersInfo>(object::object_address(&collection)).holders, i);
      if (holder.owner == owner) {
        balance = balance + 1;
      }
    };
    balance
  }

  #[test_only]
  public fun get_fa_metadata_address_for_test(collection_address: address): address {
    get_fa_metadata_address(collection_address)
  }

  #[test_only]
  public fun get_collection_404_metadata_for_test(metadata_address: address): Object<Metadata> acquires MetadataManager {
    fungible_asset::mint_ref_metadata(&borrow_global<MetadataManager>(metadata_address).mint_ref)
  }
  #[test_only]
  public fun get_collection_404_collection_for_test(metadata_address: address): Object<Collection> acquires MetadataManager {
    borrow_global<MetadataManager>(metadata_address).collection
  }

  #[test_only]
  public fun mint_for_test(creator: &signer, collection_address: address, description: String, name: String, uri: String): address
  acquires TokenManager, MetadataManager, HoldersInfo {
    mint_internal(creator, collection_address, description, name, uri)
  }
}