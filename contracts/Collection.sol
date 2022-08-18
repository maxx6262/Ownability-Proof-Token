// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Collection
 * @dev Create ERC721 standard token to manage collections of NFT supplied by users
 *  => Collection Global Contrat is contract providing unique Collection token to manage supply and auction of tokens minted through collection
 *  => anyone can make Collection with maxSuppling amount of token 
 *      -> Any Collection Owner will get new more interesting features as 
 *      -> to get fees levels to be paid for any transfer of token
 *        --=> Soon be able to manage part of IPFS linked into Metadata to improve utility of tokens.
 * ***********************************
 * ====  CURRENT BASED FEATURES ===
 *      Proof of ownability from minted token
 *      Mint auction
 *      place item on Sale (fixed price, limited time)
 *      place item on auction (limited time, more interesting bids being >= last amount owner would find offer acceptable
 *      Transferrable (with settable fees)
 *          ************************************
 * ==== FEATURES CURRENTLY on TEST PHASE = to be added soon ! === 
 *      Metadata management from both contract and collection 
 *      Link with IPFS (visual, storing data...)
 */
contract Collection is ERC721 {
    using Strings       for         uint256;
    using Counters      for         Counters.Counter;

    string                          public      constant        tokenName   =   "Collection of Ownability Proof Token";
    string                          public      constant        tokenSymbol =   "COLLECT";
    
    uint256                         public                      transferFixedFees           =   0;
    uint256                         public                      transferLastPricePartFees   =   0;
    
    
    struct collection {
        string          name;
        string          description;
        uint256         maxSupply;
        uint256         totalSupply;
        uint256         mintFees;
        uint256         transferFixedFees;
        uint256         transferLastPricePercentFees;
    }

    Counters.Counter                private                     _collectionIds;
    mapping(uint256 => collection)  private                     _collections;  
    mapping(uint256 => address)     private                     _collectionOwner;
    mapping(uint256 => uint256)     private                     _collectionTotalClaimableFees;

    constructor() ERC721(tokenName, tokenSymbol) {}
        // At this moment of contract development, we don't add additional feature but most extensions of ERC721 would be added here

    // Modifier
    modifier onlyExistingCollection(uint256 collectionId) {
        require(isExistingCollection(collectionId), 
            "Ownability Proof Token: Collection ID not foundable");
        _;
    }

    function collectionNameOf(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (string memory) {
        return (_collections[collectionId].name);
    }
    function collectionDescriptionOf(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (string memory) {
            return (_collections[collectionId].description);
    }
    function ownerOfCollectionId(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (address) {
            return (_collectionOwner[collectionId]);
    }
    function maxSupplyOfCollectionId(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (uint256) {
            return (_collections[collectionId].maxSupply);
    }    
    function currentSupplyOfCollectionId(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (uint256) {
            return (_collections[collectionId].totalSupply);
    }
    function isMintableCollection(uint256 collectionId) public view
        onlyExistingCollection(collectionId) returns (bool) {
            return (maxSupplyOfCollectionId(collectionId) > currentSupplyOfCollectionId(collectionId));
    }
    function mintableTokenSupplyFromCollectionId(uint256 collectionId) public view
        onlyExistingCollection(collectionId) returns (uint256) {
            return (maxSupplyOfCollectionId(collectionId) - currentSupplyOfCollectionId(collectionId));
    }
    function claimableAmountCollectionPaidFees(uint256 collectionId)  public  view 
        onlyExistingCollection(collectionId) returns (uint256) {
            return (_collectionTotalClaimableFees[collectionId]);
    }


    function _newCollection(
        string memory _collectionName, 
        string memory _collectionDescription, 
        uint256 _collectionMaxSupply, 
        uint256 _initialMintFees) private pure returns (collection memory) {
            return collection(
                _collectionName,
                _collectionDescription,
                _collectionMaxSupply,
                0,
                _initialMintFees,
                0,
                0);
        }

    function storeNewCollection(collection memory newCollection, address _owner) private {
        uint256 _newCollectionId                              =       _collectionIds.current();
        _collections[_newCollectionId]                        =       newCollection;
        _collectionOwner[_newCollectionId]                    =       _owner;
        _collectionTotalClaimableFees[_newCollectionId]       =       0;
        _collectionIds.increment();
    }
         /** *****************************************************************************************************************************************************************
         *                                                                                                                                                                  *
         * @dev Collection is Ownable object that allowes owner                                                                                                             *
         *  - to manage minter auction to supply maxSupply amount of token to interested account                                                                            *
         *  - to get a way to involve accounts to claim minted token, owner could set                                                                                       *
         *  - minting Fees, that is fixed amount collection get when user mints new token                                                                                   *
         *  - to manage secondary market, new rules have been created and settable by collection owner:                                                                     *
         * =================================================================================================================================================================*
         *  When any transfer of token is requested, multiple fees amount would be added at transaction to improve collection management and contract lifecycle             *
         *==================================================================================================================================================================*
         * CONTRACT GLOBAL FEES :                                                                                                                                           *
         * 1. globalContractFixedFeesAmount  = 0.0005 gwei                                                                                                                  *
         *     -> this value might be settable through future gouvernance to created                                                                                        *
         *   2. globalContractVariableFeesFromLastRecordedPricePercentage = 0.1 percent                                                                                     *
         *     -> this value might be settable through future gouvernance to created                                                                                        *
         *==================================================================================================================================================================*
         * COLLECTION FEES LEVEL                                                                                                                                            *
         * 1. collectionFixedFeesAmount  ( default = 0)                                                                                                                     *
         *     -> value >= 0 && value < mintFeesOfCollection                                                                                                                *
         *     -> settable by Collection owner                                                                                                                              *
         *     -> when full minted supplied token, Collection fees could only be set on decreasing direction                                                                *
         * 2.collectionVariableFeesBasedOnLastPricePercentage ( default = 0 )                                                                                               *
         *     -> percentageValue >= 0% and percentageValue < 100 (i.e. give back all price to collection)                                                                  *
         *     -> settable by collection owner                                                                                                                              *
         *     -> when full minted supplied token, Collection fees could only be set on decreasing direction                                                                *
         ********************************************************************************************************************************************************************
         *                                                                                                                                                                  *
         *       => IN CASE SUM OF ALL FEES AMOUNT BE OVER LASTPRICE + MINTFEES, TOTAL COLLECTION FEES WILL BE MAX(MINTFEES, LASTPRICE)                                     *
         ********************************************************************************************************************************************************************/ 
        function setCollectionTransferFees(uint256 _collectionId ,uint256 _newTransferFixedFees, uint256 _newTransferPricePercentFees) external {
            require(msg.sender == _collectionOwner[_collectionId], 
            "Ownability Proof Token: Only collection Ower car perform");
        require(_newTransferFixedFees >= 0 && _newTransferFixedFees < _collections[_collectionId].mintFees, 
            "Ownability Proof Token: New Fixed Transfer Fees cannot be set under null value or over mint auction fees for collection");
        require(_newTransferPricePercentFees >= 0 && _newTransferPricePercentFees < 100, 
            "Ownability Proof Token: New Transfer fees based on percentage value of last sale Price has to be positive, under 100 value sounding as total buying amount sent to collection and contract");
        _collections[_collectionId].transferFixedFees = _newTransferFixedFees;
        _collections[_collectionId].transferLastPricePercentFees = _newTransferPricePercentFees;

        transferFixedFees           = _newTransferFixedFees;
        transferLastPricePartFees   = _newTransferPricePercentFees;
    }
    

    function isExistingCollection(uint256 collectionId) public view returns (bool) {
        return collectionId < _collectionIds.current();
    }

    function loadCollectionFromId(uint256 collectionId) public view 
        onlyExistingCollection(collectionId) returns (collection memory) {
            return _collections[collectionId];    
    }function mintFeesOfCollectionId(uint256 collectionId) public view
        onlyExistingCollection(collectionId) returns (uint256) {
            require(isMintableCollection(collectionId), "Ownability Proof Token: No more mintable token from collection");
            return _collections[collectionId].mintFees;
        }
    function mintableSupplyOfCollectionId(uint256 collectionId) public view
        onlyExistingCollection(collectionId) returns (uint256) {
            require(isMintableCollection(collectionId), "Ownability Proof Token: Collection has still nomore mintable token");
            return _collections[collectionId].maxSupply - _collections[collectionId].totalSupply;
    }
}
