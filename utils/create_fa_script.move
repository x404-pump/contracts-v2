script {
  use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
  use aptos_framework::object::{Self, Object};
  use aptos_framework::primary_fungible_store;
  use std::error;
  use std::signer;
  use std::string::utf8;
  use std::option;
  
  const ASSET_SYMBOL: vector<u8> = b"B";

  fun main(admin: &signer) {
    // Creates a non-deletable object with a named address based on our ASSET_SYMBOL
    let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);
    
    // Create the FA's Metadata with your name, symbol, icon, etc.
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      constructor_ref,
      option::none(),
      utf8(b"B"), /* name */
      utf8(ASSET_SYMBOL), /* symbol */
      8, /* decimals */
      utf8(b"http://example.com/favicon.ico"), /* icon */
      utf8(b"http://example.com"), /* project */
    );

    let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
    let fa = fungible_asset::mint(&mint_ref, 100000_00000000);
    primary_fungible_store::deposit(signer::address_of(admin), fa);
  }

}