// Copyright (C) MrCyjaneK and monero_c contributors
// https://github.com/MrCyjaneK/monero_c
//
// This library is free software: you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this library. If not, see <https://www.gnu.org/licenses/>.

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>
#include "monero_checksum.h"

#ifdef __cplusplus
extern "C"
{
#endif

#ifdef __MINGW32__
    #define ADDAPI __declspec(dllexport)
#else
    #define ADDAPI __attribute__((__visibility__("default")))
#endif

// namespace Monero {
// enum NetworkType : uint8_t {
//     MAINNET = 0,
static const int NetworkType_MAINNET = 0;
//     TESTNET,
static const int NetworkType_TESTNET = 1;
//     STAGENET
static const int NetworkType_STAGENET = 2;
// };
//     namespace Utils {
//         bool isAddressLocal(const std::string &hostaddr);
//         void onStartup();
//     }
//     template<typename T>
//     class optional {
//       public:
//         optional(): set(false) {}
//         optional(const T &t): t(t), set(true) {}
//         const T &operator*() const { return t; }
//         T &operator*() { return t; }
//         operator bool() const { return set; }
//       private:
//         T t;
//         bool set;
//     };

// struct PendingTransaction
// {
//     enum Status {
//         Status_Ok,
static const int PendingTransactionStatus_Ok = 0;
//         Status_Error,
static const int PendingTransactionStatus_Error = 1;
//         Status_Critical
static const int PendingTransactionStatus_Critical = 2;
//     };
//     enum Priority {
//         Priority_Default = 0,
static const int Priority_Default = 0;
//         Priority_Low = 1,
static const int Priority_Low = 1;
//         Priority_Medium = 2,
static const int Priority_Medium = 2;
//         Priority_High = 3,
static const int Priority_High = 3;
//         Priority_Last
static const int Priority_Last = 4;
//     };
//     virtual ~PendingTransaction() = 0;
//     virtual int status() const = 0;
extern ADDAPI int MONERO_PendingTransaction_status(void* pendingTx_ptr);
//     virtual std::string errorString() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_errorString(void* pendingTx_ptr);
//     virtual bool commit(const std::string &filename = "", bool overwrite = false) = 0;
extern ADDAPI bool MONERO_PendingTransaction_commit(void* pendingTx_ptr, const char* filename, bool overwrite);
extern ADDAPI const char* MONERO_PendingTransaction_commitUR(void* pendingTx_ptr, int max_fragment_length);
//     virtual uint64_t amount() const = 0;
extern ADDAPI uint64_t MONERO_PendingTransaction_amount(void* pendingTx_ptr);
//     virtual uint64_t dust() const = 0;
extern ADDAPI uint64_t MONERO_PendingTransaction_dust(void* pendingTx_ptr);
//     virtual uint64_t fee() const = 0;
extern ADDAPI uint64_t MONERO_PendingTransaction_fee(void* pendingTx_ptr);
//     virtual std::vector<std::string> txid() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_txid(void* pendingTx_ptr, const char* separator);
//     virtual uint64_t txCount() const = 0;
extern ADDAPI uint64_t MONERO_PendingTransaction_txCount(void* pendingTx_ptr);
//     virtual std::vector<uint32_t> subaddrAccount() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_subaddrAccount(void* pendingTx_ptr, const char* separator);
//     virtual std::vector<std::set<uint32_t>> subaddrIndices() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_subaddrIndices(void* pendingTx_ptr, const char* separator);
//     virtual std::string multisigSignData() = 0;
extern ADDAPI const char* MONERO_PendingTransaction_multisigSignData(void* pendingTx_ptr);
//     virtual void signMultisigTx() = 0;
extern ADDAPI void MONERO_PendingTransaction_signMultisigTx(void* pendingTx_ptr);
//     virtual std::vector<std::string> signersKeys() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_signersKeys(void* pendingTx_ptr, const char* separator);
//     virtual std::vector<std::string> hex() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_hex(void* pendingTx_ptr, const char* separator);
//     virtual std::vector<std::string> txKey() const = 0;
extern ADDAPI const char* MONERO_PendingTransaction_txKey(void* pendingTx_ptr, const char* separator);
// };

// struct UnsignedTransaction
// {
//     enum Status {
//         Status_Ok,
static const int UnsignedTransactionStatus_Ok = 0;
//         Status_Error,
static const int UnsignedTransactionStatus_Error = 1;
//         Status_Critical
static const int UnsignedTransactionStatus_Critical = 2;
//     };
//     virtual ~UnsignedTransaction() = 0;
//     virtual int status() const = 0;
extern ADDAPI int MONERO_UnsignedTransaction_status(void* unsignedTx_ptr);
//     virtual std::string errorString() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_errorString(void* unsignedTx_ptr);
//     virtual std::vector<uint64_t> amount() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_amount(void* unsignedTx_ptr, const char* separator);
//     virtual std::vector<uint64_t>  fee() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_fee(void* unsignedTx_ptr, const char* separator);
//     virtual std::vector<uint64_t> mixin() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_mixin(void* unsignedTx_ptr, const char* separator);
//     virtual std::string confirmationMessage() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_confirmationMessage(void* unsignedTx_ptr);
//     virtual std::vector<std::string> paymentId() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_paymentId(void* unsignedTx_ptr, const char* separator);
//     virtual std::vector<std::string> recipientAddress() const = 0;
extern ADDAPI const char* MONERO_UnsignedTransaction_recipientAddress(void* unsignedTx_ptr, const char* separator);
//     virtual uint64_t minMixinCount() const = 0;
extern ADDAPI uint64_t MONERO_UnsignedTransaction_minMixinCount(void* unsignedTx_ptr);
//     virtual uint64_t txCount() const = 0;
extern ADDAPI uint64_t MONERO_UnsignedTransaction_txCount(void* unsignedTx_ptr);
//     virtual bool sign(const std::string &signedFileName) = 0;
extern ADDAPI bool MONERO_UnsignedTransaction_sign(void* unsignedTx_ptr, const char* signedFileName);
extern ADDAPI const char* MONERO_UnsignedTransaction_signUR(void* unsignedTx_ptr, int max_fragment_length);
// };
// struct TransactionInfo
// {
//     enum Direction {
//         Direction_In,
static const int TransactionInfoDirection_In = 0;
//         Direction_Out
static const int TransactionInfoDirection_Out = 1;
//     };
//     struct Transfer {
//         Transfer(uint64_t _amount, const std::string &address);
//         const uint64_t amount;
//         const std::string address;
//     };
//     virtual ~TransactionInfo() = 0;
//     virtual int  direction() const = 0;
extern ADDAPI int MONERO_TransactionInfo_direction(void* txInfo_ptr);
//     virtual bool isPending() const = 0;
extern ADDAPI bool MONERO_TransactionInfo_isPending(void* txInfo_ptr);
//     virtual bool isFailed() const = 0;
extern ADDAPI bool MONERO_TransactionInfo_isFailed(void* txInfo_ptr);
//     virtual bool isCoinbase() const = 0;
extern ADDAPI bool MONERO_TransactionInfo_isCoinbase(void* txInfo_ptr);
//     virtual uint64_t amount() const = 0;
extern ADDAPI int64_t MONERO_TransactionInfo_amount(void* txInfo_ptr);
//     virtual uint64_t fee() const = 0;
extern ADDAPI uint64_t MONERO_TransactionInfo_fee(void* txInfo_ptr);
//     virtual uint64_t blockHeight() const = 0;
extern ADDAPI uint64_t MONERO_TransactionInfo_blockHeight(void* txInfo_ptr);
//     virtual std::string description() const = 0;
extern ADDAPI const char* MONERO_TransactionInfo_description(void* txInfo_ptr);
//     virtual std::set<uint32_t> subaddrIndex() const = 0;
extern ADDAPI const char* MONERO_TransactionInfo_subaddrIndex(void* txInfo_ptr, const char* separator);
//     virtual uint32_t subaddrAccount() const = 0;
extern ADDAPI uint32_t MONERO_TransactionInfo_subaddrAccount(void* txInfo_ptr);
//     virtual std::string label() const = 0;
extern ADDAPI const char* MONERO_TransactionInfo_label(void* txInfo_ptr);
//     virtual uint64_t confirmations() const = 0;
extern ADDAPI uint64_t MONERO_TransactionInfo_confirmations(void* txInfo_ptr);
//     virtual uint64_t unlockTime() const = 0;
extern ADDAPI uint64_t MONERO_TransactionInfo_unlockTime(void* txInfo_ptr);
//     virtual std::string hash() const = 0;
extern ADDAPI const char* MONERO_TransactionInfo_hash(void* txInfo_ptr);
//     virtual std::time_t timestamp() const = 0;
extern ADDAPI uint64_t MONERO_TransactionInfo_timestamp(void* txInfo_ptr);
//     virtual std::string paymentId() const = 0;
extern ADDAPI const char* MONERO_TransactionInfo_paymentId(void* txInfo_ptr);
//     virtual const std::vector<Transfer> & transfers() const = 0;
extern ADDAPI int MONERO_TransactionInfo_transfers_count(void* txInfo_ptr);
extern ADDAPI uint64_t MONERO_TransactionInfo_transfers_amount(void* txInfo_ptr, int index);
extern ADDAPI const char* MONERO_TransactionInfo_transfers_address(void* txInfo_ptr, int address);
// };
// struct TransactionHistory
// {
//     virtual ~TransactionHistory() = 0;
//     virtual int count() const = 0;
extern ADDAPI int MONERO_TransactionHistory_count(void* txHistory_ptr);
//     virtual TransactionInfo * transaction(int index)  const = 0;
extern ADDAPI void* MONERO_TransactionHistory_transaction(void* txHistory_ptr, int index);
//     virtual TransactionInfo * transaction(const std::string &id) const = 0;
extern ADDAPI void* MONERO_TransactionHistory_transactionById(void* txHistory_ptr, const char* id);
//     virtual std::vector<TransactionInfo*> getAll() const = 0;
//     virtual void refresh() = 0;
extern ADDAPI void MONERO_TransactionHistory_refresh(void* txHistory_ptr);
//     virtual void setTxNote(const std::string &txid, const std::string &note) = 0;
extern ADDAPI void MONERO_TransactionHistory_setTxNote(void* txHistory_ptr, const char* txid, const char* note);
// };
// struct AddressBookRow {
// public:
//     AddressBookRow(std::size_t _rowId, const std::string &_address, const std::string &_paymentId, const std::string &_description):
//         m_rowId(_rowId),
//         m_address(_address),
//         m_paymentId(_paymentId),
//         m_description(_description) {}

// private:
//     std::size_t m_rowId;
//     std::string m_address;
//     std::string m_paymentId;
//     std::string m_description;
// public:
//     std::string extra;
extern ADDAPI const char* MONERO_AddressBookRow_extra(void* addressBookRow_ptr);
//     std::string getAddress() const {return m_address;}
extern ADDAPI const char* MONERO_AddressBookRow_getAddress(void* addressBookRow_ptr);
//     std::string getDescription() const {return m_description;}
extern ADDAPI const char* MONERO_AddressBookRow_getDescription(void* addressBookRow_ptr);
//     std::string getPaymentId() const {return m_paymentId;}
extern ADDAPI const char* MONERO_AddressBookRow_getPaymentId(void* addressBookRow_ptr);
//     std::size_t getRowId() const {return m_rowId;}
extern ADDAPI size_t MONERO_AddressBookRow_getRowId(void* addressBookRow_ptr);
// };
// struct AddressBook
// {
//     enum ErrorCode {
//         Status_Ok,
static const int AddressBookErrorCodeStatus_Ok = 0;
//         General_Error,
static const int AddressBookErrorCodeGeneral_Error = 1;
//         Invalid_Address,
static const int AddressBookErrorCodeInvalid_Address = 2;
//         Invalid_Payment_Id
static const int AddressBookErrorCodeInvalidPaymentId = 3;
//     };
//     virtual ~AddressBook() = 0;
//     virtual std::vector<AddressBookRow*> getAll() const = 0;
extern ADDAPI int MONERO_AddressBook_getAll_size(void* addressBook_ptr);
extern ADDAPI void* MONERO_AddressBook_getAll_byIndex(void* addressBook_ptr, int index);
//     virtual bool addRow(const std::string &dst_addr , const std::string &payment_id, const std::string &description) = 0;
extern ADDAPI bool MONERO_AddressBook_addRow(void* addressBook_ptr, const char* dst_addr , const char* payment_id, const char* description);
//     virtual bool deleteRow(std::size_t rowId) = 0;
extern ADDAPI bool MONERO_AddressBook_deleteRow(void* addressBook_ptr, size_t rowId);
//     virtual bool setDescription(std::size_t index, const std::string &description) = 0;
extern ADDAPI bool MONERO_AddressBook_setDescription(void* addressBook_ptr, size_t rowId, const char* description);
//     virtual void refresh() = 0;
extern ADDAPI void MONERO_AddressBook_refresh(void* addressBook_ptr);
//     virtual std::string errorString() const = 0;
extern ADDAPI const char* MONERO_AddressBook_errorString(void* addressBook_ptr);
//     virtual int errorCode() const = 0;
extern ADDAPI int MONERO_AddressBook_errorCode(void* addressBook_ptr);
//     virtual int lookupPaymentID(const std::string &payment_id) const = 0;
extern ADDAPI int MONERO_AddressBook_lookupPaymentID(void* addressBook_ptr, const char* payment_id);
// };
// struct CoinsInfo
// {
//     virtual ~CoinsInfo() = 0;
//     virtual uint64_t blockHeight() const = 0;
extern ADDAPI uint64_t MONERO_CoinsInfo_blockHeight(void* coinsInfo_ptr);
//     virtual std::string hash() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_hash(void* coinsInfo_ptr);
//     virtual size_t internalOutputIndex() const = 0;
extern ADDAPI size_t MONERO_CoinsInfo_internalOutputIndex(void* coinsInfo_ptr);
//     virtual uint64_t globalOutputIndex() const = 0;
extern ADDAPI uint64_t MONERO_CoinsInfo_globalOutputIndex(void* coinsInfo_ptr);
//     virtual bool spent() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_spent(void* coinsInfo_ptr);
//     virtual bool frozen() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_frozen(void* coinsInfo_ptr);
//     virtual uint64_t spentHeight() const = 0;
extern ADDAPI uint64_t MONERO_CoinsInfo_spentHeight(void* coinsInfo_ptr);
//     virtual uint64_t amount() const = 0;
extern ADDAPI uint64_t MONERO_CoinsInfo_amount(void* coinsInfo_ptr);
//     virtual bool rct() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_rct(void* coinsInfo_ptr);
//     virtual bool keyImageKnown() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_keyImageKnown(void* coinsInfo_ptr);
//     virtual size_t pkIndex() const = 0;
extern ADDAPI size_t MONERO_CoinsInfo_pkIndex(void* coinsInfo_ptr);
//     virtual uint32_t subaddrIndex() const = 0;
extern ADDAPI uint32_t MONERO_CoinsInfo_subaddrIndex(void* coinsInfo_ptr);
//     virtual uint32_t subaddrAccount() const = 0;
extern ADDAPI uint32_t MONERO_CoinsInfo_subaddrAccount(void* coinsInfo_ptr);
//     virtual std::string address() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_address(void* coinsInfo_ptr);
//     virtual std::string addressLabel() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_addressLabel(void* coinsInfo_ptr);
//     virtual std::string keyImage() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_keyImage(void* coinsInfo_ptr);
//     virtual uint64_t unlockTime() const = 0;
extern ADDAPI uint64_t MONERO_CoinsInfo_unlockTime(void* coinsInfo_ptr);
//     virtual bool unlocked() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_unlocked(void* coinsInfo_ptr);
//     virtual std::string pubKey() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_pubKey(void* coinsInfo_ptr);
//     virtual bool coinbase() const = 0;
extern ADDAPI bool MONERO_CoinsInfo_coinbase(void* coinsInfo_ptr);
//     virtual std::string description() const = 0;
extern ADDAPI const char* MONERO_CoinsInfo_description(void* coinsInfo_ptr);
// };
// struct Coins
// {
//     virtual ~Coins() = 0;
//     virtual int count() const = 0;
extern ADDAPI int MONERO_Coins_count(void* coins_ptr);
//     virtual CoinsInfo * coin(int index)  const = 0;
extern ADDAPI void* MONERO_Coins_coin(void* coins_ptr, int index);
//     virtual std::vector<CoinsInfo*> getAll() const = 0;
extern ADDAPI int MONERO_Coins_getAll_size(void* coins_ptr);
extern ADDAPI void* MONERO_Coins_getAll_byIndex(void* coins_ptr, int index);
//     virtual void refresh() = 0;
extern ADDAPI void MONERO_Coins_refresh(void* coins_ptr);
//     virtual void setFrozen(std::string public_key) = 0;
extern ADDAPI void MONERO_Coins_setFrozenByPublicKey(void* coins_ptr, const char* public_key);
//     virtual void setFrozen(int index) = 0;
extern ADDAPI void MONERO_Coins_setFrozen(void* coins_ptr, int index);
//     virtual void thaw(int index) = 0;
extern ADDAPI void MONERO_Coins_thaw(void* coins_ptr, int index);
//     virtual void thaw(std::string public_key) = 0;
extern ADDAPI void MONERO_Coins_thawByPublicKey(void* coins_ptr, const char* public_key);
//     virtual bool isTransferUnlocked(uint64_t unlockTime, uint64_t blockHeight) = 0;
extern ADDAPI bool MONERO_Coins_isTransferUnlocked(void* coins_ptr, uint64_t unlockTime, uint64_t blockHeight);
//    virtual void setDescription(const std::string &public_key, const std::string &description) = 0;
extern ADDAPI void MONERO_Coins_setDescription(void* coins_ptr, const char* public_key, const char* description);
// };
// struct SubaddressRow {
// public:
//     SubaddressRow(std::size_t _rowId, const std::string &_address, const std::string &_label):
//         m_rowId(_rowId),
//         m_address(_address),
//         m_label(_label) {}

// private:
//     std::size_t m_rowId;
//     std::string m_address;
//     std::string m_label;
// public:
//     std::string extra;
extern ADDAPI const char* MONERO_SubaddressRow_extra(void* subaddressRow_ptr);
//     std::string getAddress() const {return m_address;}
extern ADDAPI const char* MONERO_SubaddressRow_getAddress(void* subaddressRow_ptr);
//     std::string getLabel() const {return m_label;}
extern ADDAPI const char* MONERO_SubaddressRow_getLabel(void* subaddressRow_ptr);
//     std::size_t getRowId() const {return m_rowId;}
extern ADDAPI size_t MONERO_SubaddressRow_getRowId(void* subaddressRow_ptr);
// };

// struct Subaddress
// {
//     virtual ~Subaddress() = 0;
//     virtual std::vector<SubaddressRow*> getAll() const = 0;
extern ADDAPI int MONERO_Subaddress_getAll_size(void* subaddress_ptr);
extern ADDAPI void* MONERO_Subaddress_getAll_byIndex(void* subaddress_ptr, int index);
//     virtual void addRow(uint32_t accountIndex, const std::string &label) = 0;
extern ADDAPI void MONERO_Subaddress_addRow(void* subaddress_ptr, uint32_t accountIndex, const char* label);
//     virtual void setLabel(uint32_t accountIndex, uint32_t addressIndex, const std::string &label) = 0;
extern ADDAPI void MONERO_Subaddress_setLabel(void* subaddress_ptr, uint32_t accountIndex, uint32_t addressIndex, const char* label);
//     virtual void refresh(uint32_t accountIndex) = 0;
extern ADDAPI void MONERO_Subaddress_refresh(void* subaddress_ptr, uint32_t accountIndex);
// };

// struct SubaddressAccountRow {
// public:
//     SubaddressAccountRow(std::size_t _rowId, const std::string &_address, const std::string &_label, const std::string &_balance, const std::string &_unlockedBalance):
//         m_rowId(_rowId),
//         m_address(_address),
//         m_label(_label),
//         m_balance(_balance),
//         m_unlockedBalance(_unlockedBalance) {}

// private:
//     std::size_t m_rowId;
//     std::string m_address;
//     std::string m_label;
//     std::string m_balance;
//     std::string m_unlockedBalance;
// public:
//     std::string extra;
extern ADDAPI const char* MONERO_SubaddressAccountRow_extra(void* subaddressAccountRow_ptr);
//     std::string getAddress() const {return m_address;}
extern ADDAPI const char* MONERO_SubaddressAccountRow_getAddress(void* subaddressAccountRow_ptr);
//     std::string getLabel() const {return m_label;}
extern ADDAPI const char* MONERO_SubaddressAccountRow_getLabel(void* subaddressAccountRow_ptr);
//     std::string getBalance() const {return m_balance;}
extern ADDAPI const char* MONERO_SubaddressAccountRow_getBalance(void* subaddressAccountRow_ptr);
//     std::string getUnlockedBalance() const {return m_unlockedBalance;}
extern ADDAPI const char* MONERO_SubaddressAccountRow_getUnlockedBalance(void* subaddressAccountRow_ptr);
//     std::size_t getRowId() const {return m_rowId;}
extern ADDAPI size_t MONERO_SubaddressAccountRow_getRowId(void* subaddressAccountRow_ptr);
// };

// struct SubaddressAccount
// {
//     virtual ~SubaddressAccount() = 0;
//     virtual std::vector<SubaddressAccountRow*> getAll() const = 0;
extern ADDAPI int MONERO_SubaddressAccount_getAll_size(void* subaddressAccount_ptr);
extern ADDAPI void* MONERO_SubaddressAccount_getAll_byIndex(void* subaddressAccount_ptr, int index);
//     virtual void addRow(const std::string &label) = 0;
extern ADDAPI void MONERO_SubaddressAccount_addRow(void* subaddressAccount_ptr, const char* label);
//     virtual void setLabel(uint32_t accountIndex, const std::string &label) = 0;
extern ADDAPI void MONERO_SubaddressAccount_setLabel(void* subaddressAccount_ptr, uint32_t accountIndex, const char* label);
//     virtual void refresh() = 0;
extern ADDAPI void MONERO_SubaddressAccount_refresh(void* subaddressAccount_ptr);
// };

// struct MultisigState {
//     MultisigState() : isMultisig(false), isReady(false), threshold(0), total(0) {}

//     bool isMultisig;
extern ADDAPI bool MONERO_MultisigState_isMultisig(void* multisigState_ptr);
//     bool isReady;
extern ADDAPI bool MONERO_MultisigState_isReady(void* multisigState_ptr);
//     uint32_t threshold;
extern ADDAPI uint32_t MONERO_MultisigState_threshold(void* multisigState_ptr);
//     uint32_t total;
extern ADDAPI uint32_t MONERO_MultisigState_total(void* multisigState_ptr);
// };


// struct DeviceProgress {
//     DeviceProgress(): m_progress(0), m_indeterminate(false) {}
//     DeviceProgress(double progress, bool indeterminate=false): m_progress(progress), m_indeterminate(indeterminate) {}

//     virtual double progress() const { return m_progress; }
extern ADDAPI bool MONERO_DeviceProgress_progress(void* deviceProgress_ptr);
//     virtual bool indeterminate() const { return m_indeterminate; }
extern ADDAPI bool MONERO_DeviceProgress_indeterminate(void* deviceProgress_ptr);

// protected:
//     double m_progress;
//     bool m_indeterminate;
// };

// struct Wallet;
// struct WalletListener
// {
//     virtual ~WalletListener() = 0;
//     virtual void moneySpent(const std::string &txId, uint64_t amount) = 0;
//     virtual void moneyReceived(const std::string &txId, uint64_t amount) = 0;
//     virtual void unconfirmedMoneyReceived(const std::string &txId, uint64_t amount) = 0;
//     virtual void newBlock(uint64_t height) = 0;
//     virtual void updated() = 0;
//     virtual void refreshed() = 0;
//     virtual void onDeviceButtonRequest(uint64_t code) { (void)code; }
//     virtual void onDeviceButtonPressed() { }
//     virtual optional<std::string> onDevicePinRequest() {
//         throw std::runtime_error("Not supported");
//     }
//     virtual optional<std::string> onDevicePassphraseRequest(bool & on_device) {
//         on_device = true;
//         return optional<std::string>();
//     }
//     virtual void onDeviceProgress(const DeviceProgress & event) { (void)event; };
//     virtual void onSetWallet(Wallet * wallet) { (void)wallet; };
// };
// struct Wallet
// {
//     enum Device {
//         Device_Software = 0,
static const int WalletDevice_Software = 0;
//         Device_Ledger = 1,
static const int WalletDevice_Ledger = 1;
//         Device_Trezor = 2
static const int WalletDevice_Trezor = 2;
//     };
//     enum Status {
//         Status_Ok,
static const int WalletStatus_Ok = 0;
//         Status_Error,
static const int WalletStatus_Error = 1;
//         Status_Critical
static const int WalletStatus_Critical = 2;
//     };
//     enum ConnectionStatus {
//         ConnectionStatus_Disconnected,
static const int WalletConnectionStatus_Disconnected = 0;
//         ConnectionStatus_Connected,
static const int WalletConnectionStatus_Connected = 1;
//         ConnectionStatus_WrongVersion
static const int WalletConnectionStatus_WrongVersion = 2;
//     };
//    enum BackgroundSyncType {
//        BackgroundSync_Off = 0,
static const int WalletBackgroundSync_Off = 0;
//        BackgroundSync_ReusePassword = 1,
static const int WalletBackgroundSync_ReusePassword = 1;
//        BackgroundSync_CustomPassword = 2
static const int BackgroundSync_CustomPassword = 2;
//    };
//     virtual ~Wallet() = 0;
extern ADDAPI void MONERO_Wallet_delete(void* wallet_ptr);
//     virtual std::string seed(const std::string& seed_offset = "") const = 0;
extern ADDAPI const char* MONERO_Wallet_seed(void* wallet_ptr, const char* seed_offset);
//     virtual std::string getSeedLanguage() const = 0;
extern ADDAPI const char* MONERO_Wallet_getSeedLanguage(void* wallet_ptr);
//     virtual void setSeedLanguage(const std::string &arg) = 0;
extern ADDAPI void MONERO_Wallet_setSeedLanguage(void* wallet_ptr, const char* arg);
//     virtual int status() const = 0;
extern ADDAPI int MONERO_Wallet_status(void* wallet_ptr);
//     virtual std::string errorString() const = 0;
extern ADDAPI const char* MONERO_Wallet_errorString(void* wallet_ptr);
//     virtual void statusWithErrorString(int& status, std::string& errorString) const = 0;
//     virtual bool setPassword(const std::string &password) = 0;
extern ADDAPI bool MONERO_Wallet_setPassword(void* wallet_ptr, const char* password);
//     virtual const std::string& getPassword() const = 0;
extern ADDAPI const char* MONERO_Wallet_getPassword(void* wallet_ptr);
//     virtual bool setDevicePin(const std::string &pin) { (void)pin; return false; };
extern ADDAPI bool MONERO_Wallet_setDevicePin(void* wallet_ptr, const char* pin);
//     virtual bool setDevicePassphrase(const std::string &passphrase) { (void)passphrase; return false; };
extern ADDAPI bool MONERO_Wallet_setDevicePassphrase(void* wallet_ptr, const char* passphrase);
//     virtual std::string address(uint32_t accountIndex = 0, uint32_t addressIndex = 0) const = 0;
extern ADDAPI const char* MONERO_Wallet_address(void* wallet_ptr, uint64_t accountIndex, uint64_t addressIndex);
//     std::string mainAddress() const { return address(0, 0); }
//     virtual std::string path() const = 0;
extern ADDAPI const char* MONERO_Wallet_path(void* wallet_ptr);
//     virtual NetworkType nettype() const = 0;
extern ADDAPI int MONERO_Wallet_nettype(void* wallet_ptr);
//     bool mainnet() const { return nettype() == MAINNET; }
//     bool testnet() const { return nettype() == TESTNET; }
//     bool stagenet() const { return nettype() == STAGENET; }
//     virtual void hardForkInfo(uint8_t &version, uint64_t &earliest_height) const = 0;
//     virtual bool useForkRules(uint8_t version, int64_t early_blocks) const = 0;
extern ADDAPI uint8_t MONERO_Wallet_useForkRules(void* wallet_ptr, uint8_t version, int64_t early_blocks);
//     virtual std::string integratedAddress(const std::string &payment_id) const = 0;
extern ADDAPI const char* MONERO_Wallet_integratedAddress(void* wallet_ptr, const char* payment_id);
//     virtual std::string secretViewKey() const = 0;
extern ADDAPI const char* MONERO_Wallet_secretViewKey(void* wallet_ptr);
//     virtual std::string publicViewKey() const = 0;
extern ADDAPI const char* MONERO_Wallet_publicViewKey(void* wallet_ptr);
//     virtual std::string secretSpendKey() const = 0;
extern ADDAPI const char* MONERO_Wallet_secretSpendKey(void* wallet_ptr);
//     virtual std::string publicSpendKey() const = 0;
extern ADDAPI const char* MONERO_Wallet_publicSpendKey(void* wallet_ptr);
//     virtual std::string publicMultisigSignerKey() const = 0;
extern ADDAPI const char* MONERO_Wallet_publicMultisigSignerKey(void* wallet_ptr);
//     virtual void stop() = 0;
extern ADDAPI void MONERO_Wallet_stop(void* wallet_ptr);
//     virtual bool store(const std::string &path) = 0;
extern ADDAPI bool MONERO_Wallet_store(void* wallet_ptr, const char* path);
//     virtual std::string filename() const = 0;
extern ADDAPI const char* MONERO_Wallet_filename(void* wallet_ptr);
//     virtual std::string keysFilename() const = 0;
extern ADDAPI const char* MONERO_Wallet_keysFilename(void* wallet_ptr);
//     virtual bool init(const std::string &daemon_address, uint64_t upper_transaction_size_limit = 0, const std::string &daemon_username = "", const std::string &daemon_password = "", bool use_ssl = false, bool lightWallet = false, const std::string &proxy_address = "") = 0;
extern ADDAPI bool MONERO_Wallet_init(void* wallet_ptr, const char* daemon_address, uint64_t upper_transaction_size_limit, const char* daemon_username, const char* daemon_password, bool use_ssl, bool lightWallet, const char* proxy_address);
//     virtual bool createWatchOnly(const std::string &path, const std::string &password, const std::string &language) const = 0;
extern ADDAPI bool MONERO_Wallet_createWatchOnly(void* wallet_ptr, const char* path, const char* password, const char* language);
//     virtual void setRefreshFromBlockHeight(uint64_t refresh_from_block_height) = 0;
extern ADDAPI void MONERO_Wallet_setRefreshFromBlockHeight(void* wallet_ptr, uint64_t refresh_from_block_height);
//     virtual uint64_t getRefreshFromBlockHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_getRefreshFromBlockHeight(void* wallet_ptr);
//     virtual void setRecoveringFromSeed(bool recoveringFromSeed) = 0;
extern ADDAPI void MONERO_Wallet_setRecoveringFromSeed(void* wallet_ptr, bool recoveringFromSeed);
//     virtual void setRecoveringFromDevice(bool recoveringFromDevice) = 0;
extern ADDAPI void MONERO_Wallet_setRecoveringFromDevice(void* wallet_ptr, bool recoveringFromDevice);
//     virtual void setSubaddressLookahead(uint32_t major, uint32_t minor) = 0;
extern ADDAPI void MONERO_Wallet_setSubaddressLookahead(void* wallet_ptr, uint32_t major, uint32_t minor);
//     virtual bool connectToDaemon() = 0;
extern ADDAPI bool MONERO_Wallet_connectToDaemon(void* wallet_ptr);
//     virtual void setDaemonAddress(const std::string &address) = 0;
//     virtual ConnectionStatus connected() const = 0;
extern ADDAPI int MONERO_Wallet_connected(void* wallet_ptr);
//     virtual void setTrustedDaemon(bool arg) = 0;
extern ADDAPI void MONERO_Wallet_setTrustedDaemon(void* wallet_ptr, bool arg);
//     virtual bool trustedDaemon() const = 0;
extern ADDAPI bool MONERO_Wallet_trustedDaemon(void* wallet_ptr);
//     virtual bool setProxy(const std::string &address) = 0;
extern ADDAPI bool MONERO_Wallet_setProxy(void* wallet_ptr, const char* address);
//     virtual uint64_t balance(uint32_t accountIndex = 0) const = 0;
extern ADDAPI uint64_t MONERO_Wallet_balance(void* wallet_ptr, uint32_t accountIndex);
//     uint64_t balanceAll() const {
//         uint64_t result = 0;
//         for (uint32_t i = 0; i < numSubaddressAccounts(); ++i)
//             result += balance(i);
//         return result;
//     }
//     virtual uint64_t unlockedBalance(uint32_t accountIndex = 0) const = 0;
extern ADDAPI uint64_t MONERO_Wallet_unlockedBalance(void* wallet_ptr, uint32_t accountIndex);
//     uint64_t unlockedBalanceAll() const {
//         uint64_t result = 0;
//         for (uint32_t i = 0; i < numSubaddressAccounts(); ++i)
//             result += unlockedBalance(i);
//         return result;
//     }
//     virtual bool watchOnly() const = 0;
//    virtual uint64_t viewOnlyBalance(uint32_t accountIndex, const std::vector<std::string> &key_images = {}) const = 0;
extern ADDAPI uint64_t MONERO_Wallet_viewOnlyBalance(void* wallet_ptr, uint32_t accountIndex);
extern ADDAPI bool MONERO_Wallet_watchOnly(void* wallet_ptr);
//     virtual bool isDeterministic() const = 0;
extern ADDAPI bool MONERO_Wallet_isDeterministic(void* wallet_ptr);
//     virtual uint64_t blockChainHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_blockChainHeight(void* wallet_ptr);
//     virtual uint64_t approximateBlockChainHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_approximateBlockChainHeight(void* wallet_ptr);
//     virtual uint64_t estimateBlockChainHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_estimateBlockChainHeight(void* wallet_ptr);
//     virtual uint64_t daemonBlockChainHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_daemonBlockChainHeight(void* wallet_ptr);
//     virtual uint64_t daemonBlockChainTargetHeight() const = 0;
extern ADDAPI uint64_t MONERO_Wallet_daemonBlockChainTargetHeight(void* wallet_ptr);
//     virtual bool synchronized() const = 0;
extern ADDAPI bool MONERO_Wallet_synchronized(void* wallet_ptr);

extern ADDAPI const char* MONERO_Wallet_bytesToWords(const char *src);
extern ADDAPI const char* MONERO_Wallet_generateAddress(const char* seed, const char* seed_offset, uint32_t accountIndex, uint32_t addressIndex, bool testnet);
extern ADDAPI const char* MONERO_Wallet_generateKey(const char* seed, const char* seed_offset, const bool privateKey, const bool spendKey);

//     static std::string displayAmount(uint64_t amount);
extern ADDAPI const char* MONERO_Wallet_displayAmount(uint64_t amount);
//     static uint64_t amountFromString(const std::string &amount);
extern ADDAPI uint64_t MONERO_Wallet_amountFromString(const char* amount);
//     static uint64_t amountFromDouble(double amount);
extern ADDAPI uint64_t MONERO_Wallet_amountFromDouble(double amount);
//     static std::string genPaymentId();
extern ADDAPI const char* MONERO_Wallet_genPaymentId();
//     static bool paymentIdValid(const std::string &paiment_id);
extern ADDAPI bool MONERO_Wallet_paymentIdValid(const char* paiment_id);
//     static bool addressValid(const std::string &str, NetworkType nettype);
extern ADDAPI bool MONERO_Wallet_addressValid(const char* str, int nettype);
//     static bool addressValid(const std::string &str, bool testnet)          // deprecated
//     {
//         return addressValid(str, testnet ? TESTNET : MAINNET);
//     }
extern ADDAPI bool MONERO_Wallet_keyValid(const char* secret_key_string, const char* address_string, bool isViewKey, int nettype);
extern ADDAPI const char* MONERO_Wallet_keyValid_error(const char* secret_key_string, const char* address_string, bool isViewKey, int nettype);
//     static bool keyValid(const std::string &secret_key_string, const std::string &address_string, bool isViewKey, NetworkType nettype, std::string &error);
//     static bool keyValid(const std::string &secret_key_string, const std::string &address_string, bool isViewKey, bool testnet, std::string &error)     // deprecated
//     {
//         return keyValid(secret_key_string, address_string, isViewKey, testnet ? TESTNET : MAINNET, error);
//     }
//     static std::string paymentIdFromAddress(const std::string &str, NetworkType nettype);
extern ADDAPI const char* MONERO_Wallet_paymentIdFromAddress(const char* strarg, int nettype);
//     static std::string paymentIdFromAddress(const std::string &str, bool testnet)       // deprecated
//     {
//         return paymentIdFromAddress(str, testnet ? TESTNET : MAINNET);
//     }
//     static uint64_t maximumAllowedAmount();
extern ADDAPI uint64_t MONERO_Wallet_maximumAllowedAmount();
//     static void init(const char *argv0, const char *default_log_base_name) { init(argv0, default_log_base_name, "", true); }
//     static void init(const char *argv0, const char *default_log_base_name, const std::string &log_path, bool console);
extern ADDAPI void MONERO_Wallet_init3(void* wallet_ptr, const char* argv0, const char* default_log_base_name, const char* log_path, bool console);
//     static void debug(const std::string &category, const std::string &str);
//     static void info(const std::string &category, const std::string &str);
//     static void warning(const std::string &category, const std::string &str);
//     static void error(const std::string &category, const std::string &str);
//     virtual void startRefresh() = 0;
//     virtual bool getPolyseed(std::string &seed, std::string &passphrase) const = 0;
extern ADDAPI const char* MONERO_Wallet_getPolyseed(void* wallet_ptr, const char* passphrase);
//     static bool createPolyseed(std::string &seed_words, std::string &err, const std::string &language = "English");
extern ADDAPI const char* MONERO_Wallet_createPolyseed(const char* language);
extern ADDAPI void MONERO_Wallet_startRefresh(void* wallet_ptr);
//     virtual void pauseRefresh() = 0;
extern ADDAPI void MONERO_Wallet_pauseRefresh(void* wallet_ptr);
//     virtual bool refresh() = 0;
extern ADDAPI bool MONERO_Wallet_refresh(void* wallet_ptr);
//     virtual void refreshAsync() = 0;
extern ADDAPI void MONERO_Wallet_refreshAsync(void* wallet_ptr);
//     virtual bool rescanBlockchain() = 0;
extern ADDAPI bool MONERO_Wallet_rescanBlockchain(void* wallet_ptr);
//     virtual void rescanBlockchainAsync() = 0;
extern ADDAPI void MONERO_Wallet_rescanBlockchainAsync(void* wallet_ptr);
//     virtual void setAutoRefreshInterval(int millis) = 0;
extern ADDAPI void MONERO_Wallet_setAutoRefreshInterval(void* wallet_ptr, int millis);
//     virtual int autoRefreshInterval() const = 0;
extern ADDAPI int MONERO_Wallet_autoRefreshInterval(void* wallet_ptr);
//     virtual void addSubaddressAccount(const std::string& label) = 0;
extern ADDAPI void MONERO_Wallet_addSubaddressAccount(void* wallet_ptr, const char* label);
//     virtual size_t numSubaddressAccounts() const = 0;
extern ADDAPI size_t MONERO_Wallet_numSubaddressAccounts(void* wallet_ptr);
//     virtual size_t numSubaddresses(uint32_t accountIndex) const = 0;
extern ADDAPI size_t MONERO_Wallet_numSubaddresses(void* wallet_ptr, uint32_t accountIndex);
//     virtual void addSubaddress(uint32_t accountIndex, const std::string& label) = 0;
extern ADDAPI void MONERO_Wallet_addSubaddress(void* wallet_ptr, uint32_t accountIndex, const char* label);
//     virtual std::string getSubaddressLabel(uint32_t accountIndex, uint32_t addressIndex) const = 0;
extern ADDAPI const char* MONERO_Wallet_getSubaddressLabel(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex);
//     virtual void setSubaddressLabel(uint32_t accountIndex, uint32_t addressIndex, const std::string &label) = 0;
extern ADDAPI void MONERO_Wallet_setSubaddressLabel(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex, const char* label);
//     virtual MultisigState multisig() const = 0;
extern ADDAPI void* MONERO_Wallet_multisig(void* wallet_ptr);
//     virtual std::string getMultisigInfo() const = 0;
extern ADDAPI const char* MONERO_Wallet_getMultisigInfo(void* wallet_ptr);
//     virtual std::string makeMultisig(const std::vector<std::string>& info, uint32_t threshold) = 0;
extern ADDAPI const char* MONERO_Wallet_makeMultisig(void* wallet_ptr, const char* info, const char* info_separator, uint32_t threshold);
//     virtual std::string exchangeMultisigKeys(const std::vector<std::string> &info, const bool force_update_use_with_caution) = 0;
extern ADDAPI const char* MONERO_Wallet_exchangeMultisigKeys(void* wallet_ptr, const char* info, const char* info_separator, bool force_update_use_with_caution);
//     virtual bool exportMultisigImages(std::string& images) = 0;
extern ADDAPI const char* MONERO_Wallet_exportMultisigImages(void* wallet_ptr, const char* separator);
//     virtual size_t importMultisigImages(const std::vector<std::string>& images) = 0;
extern ADDAPI size_t MONERO_Wallet_importMultisigImages(void* wallet_ptr, const char* info, const char* info_separator);
//     virtual bool hasMultisigPartialKeyImages() const = 0;
extern ADDAPI size_t MONERO_Wallet_hasMultisigPartialKeyImages(void* wallet_ptr);
//     virtual PendingTransaction*  restoreMultisigTransaction(const std::string& signData) = 0;
extern ADDAPI void* MONERO_Wallet_restoreMultisigTransaction(void* wallet_ptr, const char* signData);
//     virtual PendingTransaction * createTransactionMultDest(const std::vector<std::string> &dst_addr, const std::string &payment_id,
//                                                    optional<std::vector<uint64_t>> amount, uint32_t mixin_count,
//                                                    PendingTransaction::Priority = PendingTransaction::Priority_Low,
//                                                    uint32_t subaddr_account = 0,
//                                                    std::set<uint32_t> subaddr_indices = {}) = 0;
extern ADDAPI void* MONERO_Wallet_createTransactionMultDest(void* wallet_ptr, const char* dst_addr_list, const char* dst_addr_list_separator, const char* payment_id,
                                                bool amount_sweep_all, const char* amount_list, const char* amount_list_separator, uint32_t mixin_count,
                                                int pendingTransactionPriority,
                                                uint32_t subaddr_account,
                                                const char* preferredInputs, const char* preferredInputs_separator);
//     virtual PendingTransaction * createTransaction(const std::string &dst_addr, const std::string &payment_id,
//                                                    optional<uint64_t> amount, uint32_t mixin_count,
//                                                    PendingTransaction::Priority = PendingTransaction::Priority_Low,
//                                                    uint32_t subaddr_account = 0,
//                                                    std::set<uint32_t> subaddr_indices = {},
//                                                    const std::set<std::string> &preferred_inputs = {) = 0;
extern ADDAPI void* MONERO_Wallet_createTransaction(void* wallet_ptr, const char* dst_addr, const char* payment_id,
                                                    uint64_t amount, uint32_t mixin_count,
                                                    int pendingTransactionPriority,
                                                    uint32_t subaddr_account,
                                                    const char* preferredInputs, const char* separator);
extern ADDAPI void MONERO_Wallet_disposeTransaction(void* wallet_ptr, void* pendingTx_ptr);
//     virtual PendingTransaction * createSweepUnmixableTransaction() = 0;
//     virtual UnsignedTransaction * loadUnsignedTx(const std::string &unsigned_filename) = 0;
extern ADDAPI void* MONERO_Wallet_loadUnsignedTx(void* wallet_ptr, const char* unsigned_filename);
extern ADDAPI void* MONERO_Wallet_loadUnsignedTxUR(void* wallet_ptr, const char* input);
//     virtual bool submitTransaction(const std::string &fileName) = 0;
extern ADDAPI bool MONERO_Wallet_submitTransaction(void* wallet_ptr, const char* fileName);
extern ADDAPI bool MONERO_Wallet_submitTransactionUR(void* wallet_ptr, const char* input);
//     virtual void disposeTransaction(PendingTransaction * t) = 0;
//     virtual uint64_t estimateTransactionFee(const std::vector<std::pair<std::string, uint64_t>> &destinations,
//                                             PendingTransaction::Priority priority) const = 0;
extern ADDAPI uint64_t MONERO_Wallet_estimateTransactionFee(void* wallet_ptr, const char* dst_addr_list, const char* dst_addr_list_separator, const char* amount_list, const char* amount_list_separator, int priority);
//     virtual bool hasUnknownKeyImages() const = 0;
extern ADDAPI bool MONERO_Wallet_hasUnknownKeyImages(void* wallet_ptr);
//     virtual bool exportKeyImages(const std::string &filename, bool all = false) = 0;
extern ADDAPI bool MONERO_Wallet_exportKeyImages(void* wallet_ptr, const char* filename, bool all);
extern ADDAPI const char* MONERO_Wallet_exportKeyImagesUR(void* wallet_ptr, size_t max_fragment_length, bool all) ;
//     virtual bool importKeyImages(const std::string &filename) = 0;
extern ADDAPI bool MONERO_Wallet_importKeyImages(void* wallet_ptr, const char* filename);
extern ADDAPI bool MONERO_Wallet_importKeyImagesUR(void* wallet_ptr, const char* input);
//     virtual bool exportOutputs(const std::string &filename, bool all = false) = 0;
extern ADDAPI bool MONERO_Wallet_exportOutputs(void* wallet_ptr, const char* filename, bool all);
extern ADDAPI const char* MONERO_Wallet_exportOutputsUR(void* wallet_ptr, size_t max_fragment_length, bool all);
//     virtual bool importOutputs(const std::string &filename) = 0;
extern ADDAPI bool MONERO_Wallet_importOutputs(void* wallet_ptr, const char* filename);
extern ADDAPI bool MONERO_Wallet_importOutputsUR(void* wallet_ptr, const char* input);
//     virtual bool scanTransactions(const std::vector<std::string> &txids) = 0;
//     virtual bool setupBackgroundSync(const BackgroundSyncType background_sync_type, const std::string &wallet_password, const optional<std::string> &background_cache_password) = 0;
extern ADDAPI bool MONERO_Wallet_setupBackgroundSync(void* wallet_ptr, int background_sync_type, const char* wallet_password, const char* background_cache_password);
//     virtual BackgroundSyncType getBackgroundSyncType() const = 0;
extern ADDAPI int MONERO_Wallet_getBackgroundSyncType(void* wallet_ptr);
//     virtual bool startBackgroundSync() = 0;
extern ADDAPI bool MONERO_Wallet_startBackgroundSync(void* wallet_ptr);
//     virtual bool stopBackgroundSync(const std::string &wallet_password) = 0;
extern ADDAPI bool MONERO_Wallet_stopBackgroundSync(void* wallet_ptr, const char* wallet_password);
//     virtual bool isBackgroundSyncing() const = 0;
extern ADDAPI bool MONERO_Wallet_isBackgroundSyncing(void* wallet_ptr);
//     virtual bool isBackgroundWallet() const = 0;
extern ADDAPI bool MONERO_Wallet_isBackgroundWallet(void* wallet_ptr);
//     virtual TransactionHistory * history() = 0;
extern ADDAPI void* MONERO_Wallet_history(void* wallet_ptr);
//     virtual AddressBook * addressBook() = 0;
extern ADDAPI void* MONERO_Wallet_addressBook(void* wallet_ptr);
//     virtual Coins * coins() = 0;
extern ADDAPI void* MONERO_Wallet_coins(void* wallet_ptr);
//     virtual Subaddress * subaddress() = 0;
extern ADDAPI void* MONERO_Wallet_subaddress(void* wallet_ptr);
//     virtual SubaddressAccount * subaddressAccount() = 0;
extern ADDAPI void* MONERO_Wallet_subaddressAccount(void* wallet_ptr);
//     virtual void setListener(WalletListener *) = 0;
//     virtual uint32_t defaultMixin() const = 0;
extern ADDAPI uint32_t MONERO_Wallet_defaultMixin(void* wallet_ptr);
//     virtual void setDefaultMixin(uint32_t arg) = 0;
extern ADDAPI void MONERO_Wallet_setDefaultMixin(void* wallet_ptr, uint32_t arg);
//     virtual bool setCacheAttribute(const std::string &key, const std::string &val) = 0;
extern ADDAPI bool MONERO_Wallet_setCacheAttribute(void* wallet_ptr, const char* key, const char* val);
//     virtual std::string getCacheAttribute(const std::string &key) const = 0;
extern ADDAPI const char* MONERO_Wallet_getCacheAttribute(void* wallet_ptr, const char* key);
//     virtual bool setUserNote(const std::string &txid, const std::string &note) = 0;
extern ADDAPI bool MONERO_Wallet_setUserNote(void* wallet_ptr, const char* txid, const char* note);
//     virtual std::string getUserNote(const std::string &txid) const = 0;
extern ADDAPI const char* MONERO_Wallet_getUserNote(void* wallet_ptr, const char* txid);
//     virtual std::string getTxKey(const std::string &txid) const = 0;
extern ADDAPI const char* MONERO_Wallet_getTxKey(void* wallet_ptr, const char* txid);
//     virtual bool checkTxKey(const std::string &txid, std::string tx_key, const std::string &address, uint64_t &received, bool &in_pool, uint64_t &confirmations) = 0;
//     virtual std::string getTxProof(const std::string &txid, const std::string &address, const std::string &message) const = 0;
//     virtual bool checkTxProof(const std::string &txid, const std::string &address, const std::string &message, const std::string &signature, bool &good, uint64_t &received, bool &in_pool, uint64_t &confirmations) = 0;
//     virtual std::string getSpendProof(const std::string &txid, const std::string &message) const = 0;
//     virtual bool checkSpendProof(const std::string &txid, const std::string &message, const std::string &signature, bool &good) const = 0;
//     virtual std::string getReserveProof(bool all, uint32_t account_index, uint64_t amount, const std::string &message) const = 0;
//     virtual bool checkReserveProof(const std::string &address, const std::string &message, const std::string &signature, bool &good, uint64_t &total, uint64_t &spent) const = 0;
//     virtual std::string signMessage(const std::string &message, const std::string &address = "") = 0;
extern ADDAPI const char* MONERO_Wallet_signMessage(void* wallet_ptr, const char* message, const char* address);
//     virtual bool verifySignedMessage(const std::string &message, const std::string &addres, const std::string &signature) const = 0;
extern ADDAPI bool MONERO_Wallet_verifySignedMessage(void* wallet_ptr, const char* message, const char* address, const char* signature);
//     virtual std::string signMultisigParticipant(const std::string &message) const = 0;
//     virtual bool verifyMessageWithPublicKey(const std::string &message, const std::string &publicKey, const std::string &signature) const = 0;
//     virtual bool parse_uri(const std::string &uri, std::string &address, std::string &payment_id, uint64_t &amount, std::string &tx_description, std::string &recipient_name, std::vector<std::string> &unknown_parameters, std::string &error) = 0;
//     virtual std::string make_uri(const std::string &address, const std::string &payment_id, uint64_t amount, const std::string &tx_description, const std::string &recipient_name, std::string &error) const = 0;
//     virtual std::string getDefaultDataDir() const = 0;
//     virtual bool rescanSpent() = 0;
extern ADDAPI bool MONERO_Wallet_rescanSpent(void* wallet_ptr);
//     virtual void setOffline(bool offline) = 0;
extern ADDAPI void MONERO_Wallet_setOffline(void* wallet_ptr, bool offline);
//     virtual bool isOffline() const = 0;
extern ADDAPI bool MONERO_Wallet_isOffline(void* wallet_ptr);
//     virtual bool blackballOutputs(const std::vector<std::string> &outputs, bool add) = 0;
//     virtual bool blackballOutput(const std::string &amount, const std::string &offset) = 0;
//     virtual bool unblackballOutput(const std::string &amount, const std::string &offset) = 0;
//     virtual bool getRing(const std::string &key_image, std::vector<uint64_t> &ring) const = 0;
//     virtual bool getRings(const std::string &txid, std::vector<std::pair<std::string, std::vector<uint64_t>>> &rings) const = 0;
//     virtual bool setRing(const std::string &key_image, const std::vector<uint64_t> &ring, bool relative) = 0;
//     virtual void segregatePreForkOutputs(bool segregate) = 0;
extern ADDAPI void MONERO_Wallet_segregatePreForkOutputs(void* wallet_ptr, bool segregate);
//     virtual void segregationHeight(uint64_t height) = 0;
extern ADDAPI void MONERO_Wallet_segregationHeight(void* wallet_ptr, uint64_t height);
//     virtual void keyReuseMitigation2(bool mitigation) = 0;
extern ADDAPI void MONERO_Wallet_keyReuseMitigation2(void* wallet_ptr, bool mitigation);
//     virtual bool lightWalletLogin(bool &isNewWallet) const = 0;
//     virtual bool lightWalletImportWalletRequest(std::string &payment_id, uint64_t &fee, bool &new_request, bool &request_fulfilled, std::string &payment_address, std::string &status) = 0;
//     virtual bool lockKeysFile() = 0;
extern ADDAPI bool MONERO_Wallet_lockKeysFile(void* wallet_ptr);
//     virtual bool unlockKeysFile() = 0;
extern ADDAPI bool MONERO_Wallet_unlockKeysFile(void* wallet_ptr);
//     virtual bool isKeysFileLocked() = 0;
extern ADDAPI bool MONERO_Wallet_isKeysFileLocked(void* wallet_ptr);
//     virtual Device getDeviceType() const = 0;
extern ADDAPI int MONERO_Wallet_getDeviceType(void* wallet_ptr);
//     virtual uint64_t coldKeyImageSync(uint64_t &spent, uint64_t &unspent) = 0;
extern ADDAPI uint64_t MONERO_Wallet_coldKeyImageSync(void* wallet_ptr, uint64_t spent, uint64_t unspent);
//     virtual void deviceShowAddress(uint32_t accountIndex, uint32_t addressIndex, const std::string &paymentId) = 0;
extern ADDAPI const char* MONERO_Wallet_deviceShowAddress(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex);
//     virtual bool reconnectDevice() = 0;
extern ADDAPI bool MONERO_Wallet_reconnectDevice(void* wallet_ptr);
//     virtual uint64_t getBytesReceived() = 0;
extern ADDAPI uint64_t MONERO_Wallet_getBytesReceived(void* wallet_ptr);
//     virtual uint64_t getBytesSent() = 0;
extern ADDAPI uint64_t MONERO_Wallet_getBytesSent(void* wallet_ptr);
    // HIDAPI_DUMMY
extern ADDAPI bool MONERO_Wallet_getStateIsConnected();
extern ADDAPI unsigned char* MONERO_Wallet_getSendToDevice();
extern ADDAPI size_t MONERO_Wallet_getSendToDeviceLength();
extern ADDAPI unsigned char* MONERO_Wallet_getReceivedFromDevice();
extern ADDAPI size_t MONERO_Wallet_getReceivedFromDeviceLength();
extern ADDAPI bool MONERO_Wallet_getWaitsForDeviceSend();
extern ADDAPI bool MONERO_Wallet_getWaitsForDeviceReceive();
extern ADDAPI void MONERO_Wallet_setDeviceReceivedData(unsigned char* data, size_t len);
extern ADDAPI void MONERO_Wallet_setDeviceSendData(unsigned char* data, size_t len);
extern ADDAPI void MONERO_Wallet_setLedgerCallback(void (*sendToLedgerDevice)(unsigned char *command, unsigned int cmd_len));
// };

// struct WalletManager
// {
//     virtual Wallet * createWallet(const std::string &path, const std::string &password, const std::string &language, NetworkType nettype, uint64_t kdf_rounds = 1) = 0;
extern ADDAPI void* MONERO_WalletManager_createWallet(void* wm_ptr, const char* path, const char* password, const char* language, int networkType);
//     Wallet * createWallet(const std::string &path, const std::string &password, const std::string &language, bool testnet = false)      // deprecated
//     {
//         return createWallet(path, password, language, testnet ? TESTNET : MAINNET);
//     }
//     virtual Wallet * openWallet(const std::string &path, const std::string &password, NetworkType nettype, uint64_t kdf_rounds = 1, WalletListener * listener = nullptr) = 0;
extern ADDAPI void* MONERO_WalletManager_openWallet(void* wm_ptr, const char* path, const char* password, int networkType);
//     Wallet * openWallet(const std::string &path, const std::string &password, bool testnet = false)     // deprecated
//     {
//         return openWallet(path, password, testnet ? TESTNET : MAINNET);
//     }
//     virtual Wallet * recoveryWallet(const std::string &path, const std::string &password, const std::string &mnemonic,
//                                     NetworkType nettype = MAINNET, uint64_t restoreHeight = 0, uint64_t kdf_rounds = 1,
//                                     const std::string &seed_offset = {}) = 0;
extern ADDAPI void* MONERO_WalletManager_recoveryWallet(void* wm_ptr, const char* path, const char* password, const char* mnemonic, int networkType, uint64_t restoreHeight, uint64_t kdfRounds, const char* seedOffset);
//     Wallet * recoveryWallet(const std::string &path, const std::string &password, const std::string &mnemonic,
//                                     bool testnet = false, uint64_t restoreHeight = 0)           // deprecated
//     {
//         return recoveryWallet(path, password, mnemonic, testnet ? TESTNET : MAINNET, restoreHeight);
//     }
//     virtual Wallet * recoveryWallet(const std::string &path, const std::string &mnemonic, NetworkType nettype, uint64_t restoreHeight = 0) = 0;
//     Wallet * recoveryWallet(const std::string &path, const std::string &mnemonic, bool testnet = false, uint64_t restoreHeight = 0)         // deprecated
//     {
//         return recoveryWallet(path, mnemonic, testnet ? TESTNET : MAINNET, restoreHeight);
//     }
//     virtual Wallet * createWalletFromKeys(const std::string &path,
//                                                     const std::string &password,
//                                                     const std::string &language,
//                                                     NetworkType nettype,
//                                                     uint64_t restoreHeight,
//                                                     const std::string &addressString,
//                                                     const std::string &viewKeyString,
//                                                     const std::string &spendKeyString = "",
//                                                     uint64_t kdf_rounds = 1) = 0;
extern ADDAPI void* MONERO_WalletManager_createWalletFromKeys(void* wm_ptr, const char* path, const char* password, const char* language, int nettype, uint64_t restoreHeight, const char* addressString, const char* viewKeyString, const char* spendKeyString, uint64_t kdf_rounds);
//     Wallet * createWalletFromKeys(const std::string &path,
//                                   const std::string &password,
//                                   const std::string &language,
//                                   bool testnet,
//                                   uint64_t restoreHeight,
//                                   const std::string &addressString,
//                                   const std::string &viewKeyString,
//                                   const std::string &spendKeyString = "")       // deprecated
//     {
//         return createWalletFromKeys(path, password, language, testnet ? TESTNET : MAINNET, restoreHeight, addressString, viewKeyString, spendKeyString);
//     }
//     virtual Wallet * createWalletFromKeys(const std::string &path,
//                                                     const std::string &language,
//                                                     NetworkType nettype,
//                                                     uint64_t restoreHeight,
//                                                     const std::string &addressString,
//                                                     const std::string &viewKeyString,
//                                                     const std::string &spendKeyString = "") = 0;
//     Wallet * createWalletFromKeys(const std::string &path,
//                                   const std::string &language,
//                                   bool testnet,
//                                   uint64_t restoreHeight,
//                                   const std::string &addressString,
//                                   const std::string &viewKeyString,
//                                   const std::string &spendKeyString = "")           // deprecated
//     {
//         return createWalletFromKeys(path, language, testnet ? TESTNET : MAINNET, restoreHeight, addressString, viewKeyString, spendKeyString);
//     }
//     virtual Wallet * createDeterministicWalletFromSpendKey(const std::string &path,
//                                                        const std::string &password,
//                                                        const std::string &language,
//                                                        NetworkType nettype,
//                                                        uint64_t restoreHeight,
//                                                        const std::string &spendKeyString,
//                                                        uint64_t kdf_rounds = 1) = 0;
extern ADDAPI void* MONERO_WalletManager_createDeterministicWalletFromSpendKey(void* wm_ptr, const char* path, const char* password,
                                                const char* language, int nettype, uint64_t restoreHeight,
                                                const char* spendKeyString, uint64_t kdf_rounds);
//     virtual Wallet * createWalletFromDevice(const std::string &path,
//                                             const std::string &password,
//                                             NetworkType nettype,
//                                             const std::string &deviceName,
//                                             uint64_t restoreHeight = 0,
//                                             const std::string &subaddressLookahead = "",
//                                             uint64_t kdf_rounds = 1,
//                                             WalletListener * listener = nullptr) = 0;
extern ADDAPI void* MONERO_WalletManager_createWalletFromDevice(void* wm_ptr, const char* path, const char* password, int nettype, const char* deviceName, uint64_t restoreHeight, const char* subaddressLookahead, const char* viewKeyString, const char* spendKeyString, uint64_t kdf_rounds);
//     virtual Wallet * createWalletFromPolyseed(const std::string &path,
//                                               const std::string &password,
//                                               NetworkType nettype,
//                                               const std::string &mnemonic,
//                                               const std::string &passphrase = "",
//                                               bool newWallet = true,
//                                               uint64_t restore_height = 0,
//                                               uint64_t kdf_rounds = 1) = 0;
extern ADDAPI void* MONERO_WalletManager_createWalletFromPolyseed(void* wm_ptr, const char* path, const char* password,
                                                int nettype, const char* mnemonic, const char* passphrase,
                                                bool newWallet, uint64_t restore_height, uint64_t kdf_rounds);
//     virtual bool closeWallet(Wallet *wallet, bool store = true) = 0;
extern ADDAPI bool MONERO_WalletManager_closeWallet(void* wm_ptr, void* wallet_ptr, bool store);
//     virtual bool walletExists(const std::string &path) = 0;
extern ADDAPI bool MONERO_WalletManager_walletExists(void* wm_ptr, const char* path);
//     virtual bool verifyWalletPassword(const std::string &keys_file_name, const std::string &password, bool no_spend_key, uint64_t kdf_rounds = 1) const = 0;
extern ADDAPI bool MONERO_WalletManager_verifyWalletPassword(void* wm_ptr, const char* keys_file_name, const char* password, bool no_spend_key, uint64_t kdf_rounds);
//     virtual bool queryWalletDevice(Wallet::Device& device_type, const std::string &keys_file_name, const std::string &password, uint64_t kdf_rounds = 1) const = 0;
extern ADDAPI int MONERO_WalletManager_queryWalletDevice(void* wm_ptr, const char* keys_file_name, const char* password, uint64_t kdf_rounds);
//     virtual std::vector<std::string> findWallets(const std::string &path) = 0;
extern ADDAPI const char* MONERO_WalletManager_findWallets(void* wm_ptr, const char* path, const char* separator);
//     virtual std::string errorString() const = 0;
extern ADDAPI const char* MONERO_WalletManager_errorString(void* wm_ptr);
//     virtual void setDaemonAddress(const std::string &address) = 0;
extern ADDAPI void MONERO_WalletManager_setDaemonAddress(void* wm_ptr, const char* address);
//     virtual bool connected(uint32_t *version = NULL) = 0;
//     virtual uint64_t blockchainHeight() = 0;
extern ADDAPI uint64_t MONERO_WalletManager_blockchainHeight(void* wm_ptr);
//     virtual uint64_t blockchainTargetHeight() = 0;
extern ADDAPI uint64_t MONERO_WalletManager_blockchainTargetHeight(void* wm_ptr);
//     virtual uint64_t networkDifficulty() = 0;
extern ADDAPI uint64_t MONERO_WalletManager_networkDifficulty(void* wm_ptr);
//     virtual double miningHashRate() = 0;
extern ADDAPI double MONERO_WalletManager_miningHashRate(void* wm_ptr);
//     virtual uint64_t blockTarget() = 0;
extern ADDAPI uint64_t MONERO_WalletManager_blockTarget(void* wm_ptr);
//     virtual bool isMining() = 0;
extern ADDAPI bool MONERO_WalletManager_isMining(void* wm_ptr);
//     virtual bool startMining(const std::string &address, uint32_t threads = 1, bool background_mining = false, bool ignore_battery = true) = 0;
extern ADDAPI bool MONERO_WalletManager_startMining(void* wm_ptr, const char* address, uint32_t threads, bool backgroundMining, bool ignoreBattery);
//     virtual bool stopMining() = 0;
extern ADDAPI bool MONERO_WalletManager_stopMining(void* wm_ptr, const char* address);
//     virtual std::string resolveOpenAlias(const std::string &address, bool &dnssec_valid) const = 0;
extern ADDAPI const char* MONERO_WalletManager_resolveOpenAlias(void* wm_ptr, const char* address, bool dnssec_valid);
//     static std::tuple<bool, std::string, std::string, std::string, std::string> checkUpdates(
//         const std::string &software,
//         std::string subdir,
//         const char *buildtag = nullptr,
//         const char *current_version = nullptr);
//     virtual bool setProxy(const std::string &address) = 0;
extern ADDAPI bool MONERO_WalletManager_setProxy(void* wm_ptr, const char* address);
// };

static const int LogLevel_Silent = -1;
static const int LogLevel_0 = 0;
static const int LogLevel_1 = 1;
static const int LogLevel_2 = 2;
static const int LogLevel_3 = 3;
static const int LogLevel_4 = 4;
static const int LogLevel_Min = -1;
static const int LogLevel_Max = 4;

// struct WalletManagerFactory
// {
//     enum LogLevel {
//         LogLevel_Silent = -1,
//         LogLevel_0 = 0,
//         LogLevel_1 = 1,
//         LogLevel_2 = 2,
//         LogLevel_3 = 3,
//         LogLevel_4 = 4,
//         LogLevel_Min = LogLevel_Silent,
//         LogLevel_Max = LogLevel_4
//     };
//     static WalletManager * getWalletManager();
extern ADDAPI void* MONERO_WalletManagerFactory_getWalletManager();
//     static void setLogLevel(int level);
extern ADDAPI void MONERO_WalletManagerFactory_setLogLevel(int level);
//     static void setLogCategories(const std::string &categories);
extern ADDAPI void MONERO_WalletManagerFactory_setLogCategories(const char* categories);
// };
// }

extern ADDAPI void MONERO_DEBUG_test0();
extern ADDAPI bool MONERO_DEBUG_test1(bool x);
extern ADDAPI int MONERO_DEBUG_test2(int x);
extern ADDAPI uint64_t MONERO_DEBUG_test3(uint64_t x);
extern ADDAPI void* MONERO_DEBUG_test4(uint64_t x);
extern ADDAPI const char* MONERO_DEBUG_test5();
extern ADDAPI const char* MONERO_DEBUG_test5_std();
extern ADDAPI bool MONERO_DEBUG_isPointerNull(void* wallet_ptr);

// cake world

extern ADDAPI void* MONERO_cw_getWalletListener(void* wallet_ptr);
extern ADDAPI void MONERO_cw_WalletListener_resetNeedToRefresh(void* cw_walletListener_ptr);
extern ADDAPI bool MONERO_cw_WalletListener_isNeedToRefresh(void* cw_walletListener_ptr);
extern ADDAPI bool MONERO_cw_WalletListener_isNewTransactionExist(void* cw_walletListener_ptr);
extern ADDAPI void MONERO_cw_WalletListener_resetIsNewTransactionExist(void* cw_walletListener_ptr);
extern ADDAPI uint64_t MONERO_cw_WalletListener_height(void* cw_walletListener_ptr);

extern ADDAPI void MONERO_free(void* ptr);

extern ADDAPI const char* MONERO_checksum_wallet2_api_c_h();
extern ADDAPI const char* MONERO_checksum_wallet2_api_c_cpp();
extern ADDAPI const char* MONERO_checksum_wallet2_api_c_exp();

// Monero core version compiled into the prebuilt library (monero src/version.cpp.in ->
// libversion.a), e.g. "0.18.5.1-c1b843525". Returns a pointer to a static string owned by
// the library - do NOT MONERO_free() it.
extern ADDAPI const char* MONERO_VERSION_getFull();
extern ADDAPI const char* MONERO_VERSION_getShort();

#ifdef __cplusplus
}
#endif
