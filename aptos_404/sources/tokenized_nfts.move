module aptos_404::tokenized_nfts {
  use std::signer;
  use std::string::{Self, String};
  use std::option::{Self, Option};
  use std::vector::{Self};
  use aptos_std::smart_vector::{Self, SmartVector};
  use aptos_framework::object::{Self, Object, ConstructorRef, TransferRef, ExtendRef};
  use aptos_framework::primary_fungible_store::{Self};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, TransferRef as FungibleTransferRef, MintRef};
  use aptos_framework::event::{Self};
  use aptos_token_objects::collection::{Self, Collection};
  use aptos_token_objects::token::{Self};
  use aptos_token_objects::royalty::{Royalty};
  use aptos_framework::function_info::{Self, FunctionInfo};
  use aptos_framework::randomness::{Self};
  use aptos_framework::dispatchable_fungible_asset::{Self};

  #[test_only]
  friend aptos_404::tokenized_nfts_test;

  const DECIMALs: u8 = 8;
  const ONE_FA_VALUE: u64 = 100_000_000;

  // Errors

  /// Max supply can only be less than or equal to 1000000
  const EINVALID_MAX_SUPPLY: u64 = 1;
  /// Sender didn't invoke commit before withdrawing or depositing
  const EREVEALED_INFO: u64 = 2;
  /// There's not enough token owned by sender or deployer
  const ENOT_ENOUGH_TOKEN_OWNED: u64 = 3;
  /// Transferer is the same as recipient
  const EINVALID_RECIPIENT: u64 = 4;
  /// Mismatch in batch's vectors's length
  const EBATCH_LENGTH_MISMATCH: u64 = 5;
  /// Sender doesn't own any token
  const ENO_TOKEN_OWNED: u64 = 6;

  #[event]
  struct CollectionCreated has drop, store {
    collection_address: address,
    collection_name: String,
    collection_description: String,
    collection_uri: String,
    collection_creator: address,
    supply: u64,
  }

  #[event]
  struct NftMinted has drop, store {
    collection_address: address,
    nft_address: address,
  }

  #[event]
  struct TokenWithdraw has drop, store {
    from: address,
    amount: u64,
  }

  #[event]
  struct TokenDeposit has drop, store {
    to: address,
    amount: u64,
  }

  #[event]
  struct NftWithdraw has drop, store {
    from: address,
    nft_address: address,
  }

  #[event]
  struct NftDeposit has drop, store {
    to: address,
    nft_address: address,
  }

  // store under nfts address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct TokenManager has key {
    collection: Object<Collection>,
    transfer_ref: TransferRef,
  }

  // store under metadata address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct MetadataManager has key {
    collection: Object<Collection>,
    mint_ref: MintRef,
  }

  // store under metadata address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct FAManagedRef has key {
    fa_transfer_ref: FungibleTransferRef
  }

  // store under protocol address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct DispatchFunctionInfo has key {
    deposit_override: FunctionInfo,
    withdraw_override: FunctionInfo,
  }

  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct OwnerInfo has key, store, copy, drop {
    owner: address, 
    token: Object<TokenManager>,
  }

  // store under collection address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct HoldersInfo has key {
    holders: SmartVector<OwnerInfo>,
  }

  // store under collection address
  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct CollectionInfo has key {
    extend_ref: ExtendRef,
  }

  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct CommitedWithdrawInfo has key {
    permutation: SmartVector<u64>,
    revealed: bool,
  }

  #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
  struct CommitedDepositInfo has key {
    permutation: SmartVector<u64>,
    revealed: bool,
  }

  fun init_module(account_signer: &signer) {
    let deposit_override = function_info::new_function_info(
      account_signer, 
      string::utf8(b"tokenized_nfts"),
      string::utf8(b"deposit")
    );
    let withdraw_override = function_info::new_function_info(
      account_signer,
      string::utf8(b"tokenized_nfts"),
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
  public fun get_fa_metadata_address(collection_address: address): address {
    let collection_object = object::address_to_object<Collection>(collection_address);
    let creator = collection::creator<Collection>(collection_object);
    let name = collection::name<Collection>(collection_object);
    let metadata_seed = get_fa_metadata_seed(name);
    object::create_object_address(&creator, *string::bytes(&metadata_seed))
  }

  fun get_amount_withdrawn<T: key>(store: Object<T>, amount: u64): u64 {
    let balance_before = fungible_asset::balance<T>(store);
    let balance_after = balance_before - amount;
    let amount_nft_withdrawn = balance_before / ONE_FA_VALUE - balance_after / ONE_FA_VALUE;
    amount_nft_withdrawn
  }

  fun get_amount_deposited<T: key>(store: Object<T>, amount: u64): u64 {
    let balance_before = fungible_asset::balance<T>(store);
    let balance_after = balance_before + amount;
    let amount_nft_deposited = balance_after / ONE_FA_VALUE - balance_before / ONE_FA_VALUE;
    amount_nft_deposited
  }

  public fun withdraw<T: key>(
    store: Object<T>,
    amount: u64,
    transfer_ref: &FungibleTransferRef,
  ): FungibleAsset acquires MetadataManager, HoldersInfo, TokenManager, CommitedWithdrawInfo {
    let owner = object::owner<T>(store);
    let metadata = fungible_asset::store_metadata<T>(store);
    let metadata_manager = borrow_global<MetadataManager>(object::object_address<Metadata>(&metadata));
    let collection_address = object::object_address<Collection>(&metadata_manager.collection);
    let commited_withdraw_info = borrow_global_mut<CommitedWithdrawInfo>(collection_address);
    assert!(commited_withdraw_info.revealed == false, EREVEALED_INFO);
    commited_withdraw_info.revealed = true;

    let amount_nft_withdrawn = get_amount_withdrawn(store, amount);
    let metadata = fungible_asset::store_metadata<T>(store);

    let collection_object = borrow_global<MetadataManager>(object::object_address(&metadata)).collection;
    let collection_address = object::object_address(&collection_object);
    let collection_supply_option = collection::count<Collection>(collection_object);
    let collection_supply = option::extract(&mut collection_supply_option);
    for (i in 0..collection_supply) {
      if (amount_nft_withdrawn == 0) break;
      let index = smart_vector::borrow(&commited_withdraw_info.permutation, i);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(collection_address).holders, *index);
      if (holder.owner != owner) continue;
      let nft = holder.token;
      let token404 = borrow_global<TokenManager>(object::object_address(&nft));
      let nft_linear_transfer_ref = object::generate_linear_transfer_ref(&token404.transfer_ref);
      object::transfer_with_ref(nft_linear_transfer_ref, @aptos_404);
      holder.owner = @aptos_404;
      amount_nft_withdrawn = amount_nft_withdrawn - 1;
      event::emit<NftWithdraw>(NftWithdraw {
        from: owner,
        nft_address: object::object_address(&nft),
      });
    };
    assert!(amount_nft_withdrawn == 0, ENOT_ENOUGH_TOKEN_OWNED);

    event::emit<TokenWithdraw>(TokenWithdraw {
      from: owner,
      amount,
    });

    fungible_asset::withdraw_with_ref<T>(
      transfer_ref,
      store,
      amount,
    )
  }

  public fun deposit<T: key>(
    store: Object<T>,
    fa: FungibleAsset,
    transfer_ref: &FungibleTransferRef,
  ) acquires TokenManager, HoldersInfo, MetadataManager, CommitedDepositInfo {

    let metadata = fungible_asset::store_metadata<T>(store);
    let metadata_manager = borrow_global<MetadataManager>(object::object_address<Metadata>(&metadata));
    let collection_address = object::object_address<Collection>(&metadata_manager.collection);
    let commited_deposit_info = borrow_global_mut<CommitedDepositInfo>(collection_address);
    assert!(commited_deposit_info.revealed == false, EREVEALED_INFO);
    commited_deposit_info.revealed = true;

    let amount_nft_deposited = get_amount_deposited(store, fungible_asset::amount(&fa));
    let metadata = fungible_asset::store_metadata<T>(store);
    let owner = object::owner<T>(store);
    let collection_object = borrow_global<MetadataManager>(object::object_address(&metadata)).collection;
    let collection_address = object::object_address(&collection_object);
    let collection_supply_option = collection::count<Collection>(collection_object);
    let collection_supply = option::extract(&mut collection_supply_option);

    for (i in 0..collection_supply) {
      if (amount_nft_deposited == 0) break;
      let index = smart_vector::borrow(&commited_deposit_info.permutation, i);
      let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(collection_address).holders, *index);
      if (holder.owner != @aptos_404) continue;
      let nft = holder.token;
      let token404 = borrow_global<TokenManager>(object::object_address(&nft));
      let nft_linear_transfer_ref = object::generate_linear_transfer_ref(&token404.transfer_ref);
      object::transfer_with_ref(nft_linear_transfer_ref, owner);
      holder.owner = owner;
      amount_nft_deposited = amount_nft_deposited - 1;
      event::emit<NftDeposit>(NftDeposit {
        to: owner,
        nft_address: object::object_address(&nft),
      });
    };
    assert!(amount_nft_deposited == 0, ENOT_ENOUGH_TOKEN_OWNED);
    event::emit<TokenDeposit>(TokenDeposit {
      to: owner,
      amount: fungible_asset::amount(&fa),
    });

    fungible_asset::deposit_with_ref<T>(
      transfer_ref,
      store,
      fa,
    );
  }

  fun create_collection_internal(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String): ConstructorRef acquires DispatchFunctionInfo {

    assert!(supply > 0 && supply <= 1_000_000, EINVALID_MAX_SUPPLY);

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
    let function_override = borrow_global<DispatchFunctionInfo>(@aptos_404);
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
    move_to(&collection_signer, CollectionInfo {
      extend_ref: object::generate_extend_ref(&collection_constructor_ref),
    });
    event::emit<CollectionCreated>(CollectionCreated {
      collection_address: object::address_from_constructor_ref(&collection_constructor_ref),
      collection_name: name,
      collection_description: description,
      collection_uri: uri,
      collection_creator: signer::address_of(creator),
      supply,
    });

    (collection_constructor_ref)
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
    object::transfer<TokenManager>(creator, nft_object, @aptos_404);
    object::disable_ungated_transfer(nft_transfer_ref);
    smart_vector::push_back(&mut borrow_global_mut<HoldersInfo>(collection_address).holders, OwnerInfo {
      owner: @aptos_404,
      token: nft_object,
    });
    let metadata_address = get_fa_metadata_address(collection_address);
    primary_fungible_store::mint(&borrow_global<MetadataManager>(metadata_address).mint_ref, @aptos_404, ONE_FA_VALUE);

    event::emit<NftMinted>(NftMinted {
      collection_address,
      nft_address: signer::address_of(&nft_signer)
    });
    signer::address_of(&nft_signer)
  }

  public fun create_collection(creator: &signer, description: String, supply: u64, name: String, uri: String, fa_symbol: String, fa_icon: String): ConstructorRef acquires DispatchFunctionInfo {
    create_collection_internal(creator, description, supply, name, option::none(), uri, fa_symbol, fa_icon)
  }

  #[lint::allow_unsafe_randomness]
  public fun create_collection_and_mint(creator: &signer, description: String, supply: u64, name: String, uri: String, fa_symbol: String, fa_icon: String, descriptions: vector<String>, names: vector<String>, uris: vector<String>) : (ConstructorRef, FungibleAsset) acquires TokenManager, FAManagedRef, MetadataManager, HoldersInfo, CommitedWithdrawInfo, DispatchFunctionInfo, CollectionInfo {
    let collection_constructor_ref = create_collection_internal(creator, description, supply, name, option::none(), uri, fa_symbol, fa_icon);
    let collection_address = object::address_from_constructor_ref(&collection_constructor_ref);
    mint_batch_404s_in_collection(creator, object::address_from_constructor_ref(&collection_constructor_ref), descriptions, names, uris);
    // let transfer_ref = borrow_global<FAManagedRef>(@aptos_404).fa_transfer_ref;
    let aptos_404_store = primary_fungible_store::ensure_primary_store_exists(@aptos_404, object::address_to_object<Metadata>(get_fa_metadata_address(collection_address)));
    commit_before_withdraw(collection_address);
    let fa = withdraw(aptos_404_store, (vector::length<String>(&descriptions) as u64) * ONE_FA_VALUE, &borrow_global<FAManagedRef>(get_fa_metadata_address(collection_address)).fa_transfer_ref);
    (collection_constructor_ref, fa)
  }

  entry public fun mint(creator: &signer, collection_address: address, description: String, name: String, uri: String)
  acquires TokenManager, MetadataManager, HoldersInfo {
    mint_internal(creator, collection_address, description, name, uri);
  }

  entry public fun mint_batch_404s_in_collection(creator: &signer, collection_address: address, descriptions: vector<String>, names: vector<String>, uris: vector<String>)
  acquires TokenManager, MetadataManager, HoldersInfo {
    assert!(vector::length<String>(&descriptions) == vector::length<String>(&names) && vector::length<String>(&names) == vector::length<String>(&uris), EBATCH_LENGTH_MISMATCH);
    for (i in 0..vector::length<String>(&descriptions)) {
      mint(creator, collection_address, *vector::borrow<String>(&descriptions, i), *vector::borrow<String>(&names, i), *vector::borrow<String>(&uris, i));
    };
  }

  entry public fun transfer(from: &signer, to: address, token_address: address) acquires TokenManager, FAManagedRef, HoldersInfo {
    assert!(signer::address_of(from) != to, EINVALID_RECIPIENT);
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
    assert!(flag == true, ENO_TOKEN_OWNED);
    let holder = smart_vector::borrow_mut<OwnerInfo>(&mut borrow_global_mut<HoldersInfo>(object::object_address(&collection_object)).holders, index);
    holder.owner = to;
    let metadata_address = get_fa_metadata_address(object::object_address(&collection_object));
    let metadata_object = object::address_to_object<Metadata>(metadata_address);
    let from_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(from), metadata_object);
    let to_store = primary_fungible_store::ensure_primary_store_exists(to, metadata_object);
    let fa_transfer_ref = &borrow_global<FAManagedRef>(metadata_address).fa_transfer_ref;
    let fa_from = fungible_asset::withdraw_with_ref(fa_transfer_ref, from_store, ONE_FA_VALUE);
    fungible_asset::deposit_with_ref(fa_transfer_ref, to_store, fa_from);
    event::emit<NftWithdraw>(NftWithdraw {
      from: signer::address_of(from),
      nft_address: token_address,
    });
    event::emit<NftDeposit>(NftDeposit {
      to,
      nft_address: token_address,
    });
    event::emit<TokenWithdraw>(TokenWithdraw {
      from: signer::address_of(from),
      amount: ONE_FA_VALUE,
    });
    event::emit<TokenDeposit>(TokenDeposit {
      to,
      amount: ONE_FA_VALUE,
    });
  }

  fun get_collection_permuation(permutation: &mut SmartVector<u64>, collection_address: address) {
    let collection_object = object::address_to_object<Collection>(collection_address);
    let collection_supply_option = collection::count<Collection>(collection_object);
    let collection_supply = option::extract(&mut collection_supply_option);
    let random_permutation = randomness::permutation(collection_supply);
    smart_vector::add_all<u64>(permutation, random_permutation);
  }

  fun get_collection_signer(collection_address: address): signer acquires CollectionInfo {
    object::generate_signer_for_extending(&borrow_global<CollectionInfo>(collection_address).extend_ref)
  }

  #[randomness]
  entry fun entry_commit_before_withdraw(collection_address: address) acquires CollectionInfo, CommitedWithdrawInfo {
    if (exists<CommitedWithdrawInfo>(collection_address)) {
      let commited_withdraw_info = borrow_global_mut<CommitedWithdrawInfo>(collection_address);
      if (commited_withdraw_info.revealed == true) {
        get_collection_permuation(&mut commited_withdraw_info.permutation, collection_address);
        commited_withdraw_info.revealed = false;
      }
    } else {
      let collection_signer = get_collection_signer(collection_address);
      let permutation = smart_vector::new<u64>();
      get_collection_permuation(&mut permutation, collection_address);
      move_to(&collection_signer, CommitedWithdrawInfo {
        permutation,
        revealed: false,
      });
    }
  }

  #[randomness]
  entry fun entry_commit_before_deposit(collection_address: address) acquires CollectionInfo, CommitedDepositInfo {
    if (exists<CommitedDepositInfo>(collection_address)) {
      let commited_deposit_info = borrow_global_mut<CommitedDepositInfo>(collection_address);
      if (commited_deposit_info.revealed == true) {
        get_collection_permuation(&mut commited_deposit_info.permutation, collection_address);
        commited_deposit_info.revealed = false;
      }
    } else {
      let collection_signer = get_collection_signer(collection_address);
      let permutation = smart_vector::new<u64>();
      get_collection_permuation(&mut permutation, collection_address);
      move_to(&collection_signer, CommitedDepositInfo {
        permutation,
        revealed: false,
      });
    }
  }

  #[lint::allow_unsafe_randomness]
  public fun commit_before_withdraw(collection_address: address) acquires CollectionInfo, CommitedWithdrawInfo {
    if (exists<CommitedWithdrawInfo>(collection_address)) {
      let commited_withdraw_info = borrow_global_mut<CommitedWithdrawInfo>(collection_address);
      if (commited_withdraw_info.revealed == true) {
        get_collection_permuation(&mut commited_withdraw_info.permutation, collection_address);
        commited_withdraw_info.revealed = false;
      }
    } else {
      let collection_signer = get_collection_signer(collection_address);
      let permutation = smart_vector::new<u64>();
      get_collection_permuation(&mut permutation, collection_address);
      move_to(&collection_signer, CommitedWithdrawInfo {
        permutation,
        revealed: false,
      });
    }
  }

  #[lint::allow_unsafe_randomness]
  public fun commit_before_deposit(collection_address: address) acquires CollectionInfo, CommitedDepositInfo {
    if (exists<CommitedDepositInfo>(collection_address)) {
      let commited_deposit_info = borrow_global_mut<CommitedDepositInfo>(collection_address);
      if (commited_deposit_info.revealed == true) {
        get_collection_permuation(&mut commited_deposit_info.permutation, collection_address);
        commited_deposit_info.revealed = false;
      }
    } else {
      let collection_signer = get_collection_signer(collection_address);
      let permutation = smart_vector::new<u64>();
      get_collection_permuation(&mut permutation, collection_address);
      move_to(&collection_signer, CommitedDepositInfo {
        permutation,
        revealed: false,
      });
    }
  }

  #[test_only]
  public fun init_module_for_test(account_signer: &signer) {
    init_module(account_signer);
  }

  #[test_only]
  public fun create_collection_for_test(creator: &signer, description: String, supply: u64, name: String, royalty: Option<Royalty>, uri: String, fa_symbol: String, fa_icon: String): address acquires DispatchFunctionInfo {
    let ref = create_collection_internal(creator, description, supply, name, royalty, uri, fa_symbol, fa_icon);
    object::address_from_constructor_ref(&ref)
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