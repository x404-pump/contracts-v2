
module bonding_curve_launchpad::bonding_curve_launchpad {
    use std::string::{String};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use bonding_curve_launchpad::liquidity_pairs;
    use aptos_404::tokenized_nfts;
    #[test_only]
    use aptos_framework::fungible_asset;

    /// FA's name and symbol already exist on the launchpad.
    const EFA_EXISTS_ALREADY: u64 = 10;
    /// Unknown FA. Not recognized on platform.
    const EFA_DOES_NOT_EXIST: u64 = 11;
    /// FA is globally frozen for transfers.
    const EFA_FROZEN: u64 = 13;
    /// Swap amount_in is non-positive.
    const ELIQUIDITY_PAIR_SWAP_AMOUNTIN_INVALID: u64 = 110;

    //---------------------------Events---------------------------
    #[event]
    struct FungibleAssetCreated has store, drop {
        name: String,
        symbol: String,
        max_supply: u128,
        decimals: u8,
        icon_uri: String,
        project_uri: String
    }

    //---------------------------Init---------------------------
    fun init_module(_account: &signer) {
    }

    // Retrieve the FA balance of a given user's address.
    #[view]
    public fun get_balance(
        collection_address: address,
        user: address
    ): u64 {
        primary_fungible_store::balance(user, get_metadata(collection_address))
    }

    // Retrieve the Metadata object of a given FA's unique name and symbol.
    #[view]
    public fun get_metadata(
        collection_address: address
    ): Object<Metadata> {
        object::address_to_object(tokenized_nfts::get_fa_metadata_address(collection_address))
    }

    // Retrieve frozen status of a given FA's unique name and symbol, from associated `liquidity_pair` state.
    #[view]
    public fun get_is_frozen(
        collection_address: address,
    ): bool {
        liquidity_pairs::get_is_frozen_metadata(collection_address)
    }

    //---------------------------Bonding Curve Launchpad (BCL)---------------------------
    /// Participants can launch new FA's and their associated liquidity pair.
    /// Optionally, the participant can immediately perform an initial swap from APT to FA.
    #[randomness]
    entry fun create_fa_pair(
        creator: &signer,
        apt_amount_in: u64,
        description: String, supply: u64, name: String, uri: String, fa_symbol: String, fa_icon: String, descriptions: vector<String>, names: vector<String>, uris: vector<String>,
        fa_inital_price: u64
    ) {
        let (collection_constructor_ref, fa_minted) = tokenized_nfts::create_collection_and_mint(
            creator,
            description,
            supply,
            name,
            uri,
            fa_symbol,
            fa_icon,
            descriptions,
            names,
            uris
        );
        // `transfer_ref` is required for swapping in `liquidity_pair`. Otherwise, the custom withdraw function would
        // block the transfer of APT to the creator.
        // Create the liquidity pair between APT and the new FA. Include the initial creator swap, if needed.
        liquidity_pairs::register_liquidity_pair(
            collection_constructor_ref,
            creator,
            apt_amount_in,
            fa_minted,
            fa_inital_price,
            supply,
        );
    }

    /// Swap from FA to APT, or vice versa, through `liquidity_pair`.
    #[randomness]
    entry fun swap(
        account: &signer,
        collection_address: address,
        swap_to_apt: bool,
        amount_in: u64
    ) {
        // Verify the `amount_in` is valid and that the FA exists.
        assert!(amount_in > 0, ELIQUIDITY_PAIR_SWAP_AMOUNTIN_INVALID);
        // FA Object<Metadata> required for primary_fungible_store interactions.
        // `transfer_ref` is used to bypass the `is_frozen` status of the FA. Without this, the defined dispatchable
        // withdraw function would prevent the ability to transfer the participant's FA onto the liquidity pair.
        let fa_metadata_address = tokenized_nfts::get_fa_metadata_address(collection_address);
        let fa_metadata_obj = object::address_to_object<Metadata>(fa_metadata_address);
        // Initiate the swap on the associated liquidity pair.
        if (swap_to_apt) {
            liquidity_pairs::swap_fa_to_apt(collection_address, account, fa_metadata_obj, amount_in);
        } else {
            liquidity_pairs::swap_apt_to_fa(collection_address, account, fa_metadata_obj, amount_in);
        };
    }
    /// Swap from FA to APT, or vice versa, through `liquidity_pair`.
    #[view]
    public fun preview_amount_out(
        collection_address: address,
        swap_to_apt: bool,
        amount_in: u64
    ): (u64, u64, u128, u128) {
        // Verify the `amount_in` is valid and that the FA exists.
        assert!(amount_in > 0, ELIQUIDITY_PAIR_SWAP_AMOUNTIN_INVALID);
        // FA Object<Metadata> required for primary_fungible_store interactions.
        // `transfer_ref` is used to bypass the `is_frozen` status of the FA. Without this, the defined dispatchable
        // withdraw function would prevent the ability to transfer the participant's FA onto the liquidity pair.
        // Initiate the swap on the associated liquidity pair.
        if (swap_to_apt) {
            liquidity_pairs::swap_fa_to_apt_preview(collection_address, amount_in)
        } else {
            liquidity_pairs::swap_apt_to_fa_preview(collection_address, amount_in)
        }
    }

    //---------------------------Tests---------------------------
    #[test_only]
    public fun initialize_for_test(_deployer: &signer) {

    }

    #[test_only]
    public fun create_fa_pair_for_test(
        creator: &signer,
        apt_amount_in: u64,
        description: String, supply: u64, name: String, uri: String, fa_symbol: String, fa_icon: String, descriptions: vector<String>, names: vector<String>, uris: vector<String>,
        fa_inital_price: u64
    ): (address, address) {
        let (collection_constructor_ref, fa_minted) = tokenized_nfts::create_collection_and_mint(
            creator,
            description,
            supply,
            name,
            uri,
            fa_symbol,
            fa_icon,
            descriptions,
            names,
            uris
        );
        let collection_address = object::address_from_constructor_ref(&collection_constructor_ref);
        let fa_metadata_obj = fungible_asset::metadata_from_asset(&fa_minted);
        // `transfer_ref` is required for swapping in `liquidity_pair`. Otherwise, the custom withdraw function would
        // block the transfer of APT to the creator.
        // Create the liquidity pair between APT and the new FA. Include the initial creator swap, if needed.
        liquidity_pairs::register_liquidity_pair(
            collection_constructor_ref,
            creator,
            apt_amount_in,
            fa_minted,
            fa_inital_price,
            supply,
        );

        (collection_address, object::object_address(&fa_metadata_obj))
    }
}
