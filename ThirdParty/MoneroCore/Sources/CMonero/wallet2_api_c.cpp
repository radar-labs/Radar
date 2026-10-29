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

#include <inttypes.h>
#include "wallet2_api_c.h"
#include <unistd.h>
#include "helpers.hpp"
#include <cstring>
#include <thread>
#include "wallet2_api.h"
#include "monero_checksum.h"

#ifdef __cplusplus
extern "C"
{
#endif


// The code in here consists of simple wrappers, that convert
// more advanced c++ types (and function names) into simple C-compatible
// functions, so these implementations can be easly used from all languages
// that do support C interop (such as dart)
//
//
// Here is the most complex definition that we can find in the current codebase, it even includes
// a if statement - which in general I consider an anti-patter in just wrappers
//
//  _____________ void* because C++ wallet->createTransaction returns a pointer to Monero::PendingTransaction, which we don't want to have exposed in C land
// /      _____________ MONERO prefix just means that this function is using monero codebase, to not cause any symbols collision when using more than one libwallet2_api_c.so in a single program.
// |     /       _____________ Wallet is one of the classes in Monero namespace in the upstream codebase (see the include line above)
// |     |      /       _____________ aaand it is calling createTransaction function.
// |     |      |      /                  _________________________________________________________________________________
// |     |      |      |                 /                                                                                 \ All of these parameters can be found in the upstream
// |     |      |      |                |                                                                     _____________/ function definition, if something was more complex -
// void* MONERO_Wallet_createTransaction(void* wallet_ptr, const char* dst_addr, const char* payment_id,     / like std::set I've used splitString functions and introduced a new
//                                                     uint64_t amount, uint32_t mixin_count,               / parameter - separator, as it is the simplest way to get vector onto
//                                                     int pendingTransactionPriority,                     / C side from more advanced world.
//                                                     uint32_t subaddr_account,                          /
//                                                     const char* preferredInputs, const char* separator) {
//     Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr); <------------ We are converting the void* into Monero::Wallet*
//     Monero::optional<uint64_t> optAmount; <------------- optional by default
//     if (amount != 0) {------------------\ We set this optional parameter only when it isn't zero
//         optAmount = amount;             |
//     }___________________________________/
//     std::set<uint32_t> subaddr_indices = {}; ------------- Default value
//     std::set<std::string> preferred_inputs = splitString(std::string(preferredInputs), std::string(separator)); <------------- We are using helpers.cpp function to split a string into std::set
//     return wallet->createTransaction(std::string(dst_addr), std::string(payment_id),-\ const char * is getting casted onto std::string
//                                         optAmount, mixin_count,        \_____________/
//                                         PendingTransaction_Priority_fromInt(pendingTransactionPriority), <------------- special case for this function to get native type instead of int value.
//                                         subaddr_account, subaddr_indices, preferred_inputs);
// }
//
//
// One case which is not covered here is when we have to return a string
// const char* MONERO_PendingTransaction_errorString(void* pendingTx_ptr) {
//     Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
//     std::string str = pendingTx->errorString(); <------------- get the actual string from the upstream codebase
//     const std::string::size_type size = str.size(); ------------------------------\
//     char *buffer = new char[size + 1];   //we need extra char for NUL             | Copy the string onto a new memory so it won't get freed after the function returns
//     memcpy(buffer, str.c_str(), size + 1);                                        | NOTE: This requires us to call free() after we are done with the text processing
//     return buffer; ______________________________________________________________/
// }
//
//

// PendingTransaction

int MONERO_PendingTransaction_status(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->status();
    DEBUG_END()
}
const char* MONERO_PendingTransaction_errorString(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::string str = pendingTx->errorString();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
bool MONERO_PendingTransaction_commit(void* pendingTx_ptr, const char* filename, bool overwrite) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->commit(std::string(filename), overwrite);
    DEBUG_END()
}
const char* MONERO_PendingTransaction_commitUR(void* pendingTx_ptr, int max_fragment_length) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::string str = pendingTx->commitUR(max_fragment_length);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
uint64_t MONERO_PendingTransaction_amount(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->amount();
    DEBUG_END()
}
uint64_t MONERO_PendingTransaction_dust(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->dust();
    DEBUG_END()
}
uint64_t MONERO_PendingTransaction_fee(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->fee();
    DEBUG_END()
}
const char* MONERO_PendingTransaction_txid(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<std::string> txid = pendingTx->txid();
    return vectorToString(txid, std::string(separator));
    DEBUG_END()
}
uint64_t MONERO_PendingTransaction_txCount(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->txCount();
    DEBUG_END()
}
const char* MONERO_PendingTransaction_subaddrAccount(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<uint32_t> subaddrAccount = pendingTx->subaddrAccount();
    return vectorToString(subaddrAccount, std::string(separator));
    DEBUG_END()
}
const char* MONERO_PendingTransaction_subaddrIndices(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<std::set<uint32_t>> subaddrIndices = pendingTx->subaddrIndices();
    return vectorToString(subaddrIndices, std::string(separator));
    DEBUG_END()
}
const char* MONERO_PendingTransaction_multisigSignData(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::string str = pendingTx->multisigSignData();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
void MONERO_PendingTransaction_signMultisigTx(void* pendingTx_ptr) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    return pendingTx->signMultisigTx();
    DEBUG_END()
}
const char* MONERO_PendingTransaction_signersKeys(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<std::string> txid = pendingTx->signersKeys();
    return vectorToString(txid, std::string(separator));
    DEBUG_END()
}

const char* MONERO_PendingTransaction_hex(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<std::string> txid = pendingTx->hex();
    return vectorToString(txid, std::string(separator));
    DEBUG_END()
}

const char* MONERO_PendingTransaction_txKey(void* pendingTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    std::vector<std::string> txid = pendingTx->txKey();
    return vectorToString(txid, std::string(separator));
    DEBUG_END()
}

// UnsignedTransaction

int MONERO_UnsignedTransaction_status(void* unsignedTx_ptr) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return unsignedTx->status();
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_errorString(void* unsignedTx_ptr) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    std::string str = unsignedTx->errorString();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_amount(void* unsignedTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return vectorToString(unsignedTx->amount(), std::string(separator));
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_fee(void* unsignedTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return vectorToString(unsignedTx->fee(), std::string(separator));
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_mixin(void* unsignedTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return vectorToString(unsignedTx->mixin(), std::string(separator));
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_confirmationMessage(void* unsignedTx_ptr) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    std::string str = unsignedTx->confirmationMessage();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_paymentId(void* unsignedTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return vectorToString(unsignedTx->paymentId(), std::string(separator));
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_recipientAddress(void* unsignedTx_ptr, const char* separator) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return vectorToString(unsignedTx->recipientAddress(), std::string(separator));
    DEBUG_END()
}
uint64_t MONERO_UnsignedTransaction_minMixinCount(void* unsignedTx_ptr) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return unsignedTx->minMixinCount();
    DEBUG_END()
}
uint64_t MONERO_UnsignedTransaction_txCount(void* unsignedTx_ptr) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return unsignedTx->txCount();
    DEBUG_END()
}
bool MONERO_UnsignedTransaction_sign(void* unsignedTx_ptr, const char* signedFileName) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    return unsignedTx->sign(std::string(signedFileName));
    DEBUG_END()
}
const char* MONERO_UnsignedTransaction_signUR(void* unsignedTx_ptr, int max_fragment_length) {
    DEBUG_START()
    Monero::UnsignedTransaction *unsignedTx = reinterpret_cast<Monero::UnsignedTransaction*>(unsignedTx_ptr);
    std::string str = unsignedTx->signUR(max_fragment_length);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
// TransactionInfo
int MONERO_TransactionInfo_direction(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->direction();
    DEBUG_END()
}
bool MONERO_TransactionInfo_isPending(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->isPending();
    DEBUG_END()
}
bool MONERO_TransactionInfo_isFailed(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->isFailed();
    DEBUG_END()
}
bool MONERO_TransactionInfo_isCoinbase(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->isCoinbase();
    DEBUG_END()
}
int64_t MONERO_TransactionInfo_amount(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->amount();
    DEBUG_END()
}
uint64_t MONERO_TransactionInfo_fee(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->fee();
    DEBUG_END()
}
uint64_t MONERO_TransactionInfo_blockHeight(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->blockHeight();
    DEBUG_END()
}
const char* MONERO_TransactionInfo_description(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::string str = txInfo->description();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
const char* MONERO_TransactionInfo_subaddrIndex(void* txInfo_ptr, const char* separator) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::set<uint32_t> subaddrIndex = txInfo->subaddrIndex();
    return vectorToString(subaddrIndex, std::string(separator));
    DEBUG_END()
}
uint32_t MONERO_TransactionInfo_subaddrAccount(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->subaddrAccount();
    DEBUG_END()
}
const char* MONERO_TransactionInfo_label(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::string str = txInfo->label();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
uint64_t MONERO_TransactionInfo_confirmations(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->confirmations();
    DEBUG_END()
}
uint64_t MONERO_TransactionInfo_unlockTime(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->unlockTime();
    DEBUG_END()
}
const char* MONERO_TransactionInfo_hash(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::string str = txInfo->hash();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
uint64_t MONERO_TransactionInfo_timestamp(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->timestamp();
    DEBUG_END()
}
const char* MONERO_TransactionInfo_paymentId(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::string str = txInfo->paymentId();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

int MONERO_TransactionInfo_transfers_count(void* txInfo_ptr) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->transfers().size();
    DEBUG_END()
}

uint64_t MONERO_TransactionInfo_transfers_amount(void* txInfo_ptr, int index) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    return txInfo->transfers()[index].amount;
    DEBUG_END()
}

const char* MONERO_TransactionInfo_transfers_address(void* txInfo_ptr, int index) {
    DEBUG_START()
    Monero::TransactionInfo *txInfo = reinterpret_cast<Monero::TransactionInfo*>(txInfo_ptr);
    std::string str = txInfo->transfers()[index].address;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}




// TransactionHistory
int MONERO_TransactionHistory_count(void* txHistory_ptr) {
    DEBUG_START()
    Monero::TransactionHistory *txHistory = reinterpret_cast<Monero::TransactionHistory*>(txHistory_ptr);
    return txHistory->count();
    DEBUG_END()
}
void* MONERO_TransactionHistory_transaction(void* txHistory_ptr, int index) {
    DEBUG_START()
    Monero::TransactionHistory *txHistory = reinterpret_cast<Monero::TransactionHistory*>(txHistory_ptr);
    return reinterpret_cast<void*>(txHistory->transaction(index));
    DEBUG_END()
}
void* MONERO_TransactionHistory_transactionById(void* txHistory_ptr, const char* id) {
    DEBUG_START()
    Monero::TransactionHistory *txHistory = reinterpret_cast<Monero::TransactionHistory*>(txHistory_ptr);
    return reinterpret_cast<void*>(txHistory->transaction(std::string(id)));
    DEBUG_END()
}

void MONERO_TransactionHistory_refresh(void* txHistory_ptr) {
    DEBUG_START()
    Monero::TransactionHistory *txHistory = reinterpret_cast<Monero::TransactionHistory*>(txHistory_ptr);
    return txHistory->refresh();
    DEBUG_END()
}
void MONERO_TransactionHistory_setTxNote(void* txHistory_ptr, const char* txid, const char* note) {
    DEBUG_START()
    Monero::TransactionHistory *txHistory = reinterpret_cast<Monero::TransactionHistory*>(txHistory_ptr);
    return txHistory->setTxNote(std::string(txid), std::string(note));
    DEBUG_END()
}

// AddressBokRow

//     std::string extra;
const char* MONERO_AddressBookRow_extra(void* addressBookRow_ptr) {
    DEBUG_START()
    Monero::AddressBookRow *addressBookRow = reinterpret_cast<Monero::AddressBookRow*>(addressBookRow_ptr);
    std::string str = addressBookRow->extra;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getAddress() const {return m_address;}
const char* MONERO_AddressBookRow_getAddress(void* addressBookRow_ptr) {
    DEBUG_START()
    Monero::AddressBookRow *addressBookRow = reinterpret_cast<Monero::AddressBookRow*>(addressBookRow_ptr);
    std::string str = addressBookRow->getAddress();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getDescription() const {return m_description;}
const char* MONERO_AddressBookRow_getDescription(void* addressBookRow_ptr) {
    DEBUG_START()
    Monero::AddressBookRow *addressBookRow = reinterpret_cast<Monero::AddressBookRow*>(addressBookRow_ptr);
    std::string str = addressBookRow->getDescription();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getPaymentId() const {return m_paymentId;}
const char* MONERO_AddressBookRow_getPaymentId(void* addressBookRow_ptr) {
    DEBUG_START()
    Monero::AddressBookRow *addressBookRow = reinterpret_cast<Monero::AddressBookRow*>(addressBookRow_ptr);
    std::string str = addressBookRow->getPaymentId();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::size_t getRowId() const {return m_rowId;}
size_t MONERO_AddressBookRow_getRowId(void* addressBookRow_ptr) {
    DEBUG_START()
    Monero::AddressBookRow *addressBookRow = reinterpret_cast<Monero::AddressBookRow*>(addressBookRow_ptr);
    return addressBookRow->getRowId();
    DEBUG_END()
}

// AddressBook
//     virtual std::vector<AddressBookRow*> getAll() const = 0;
int MONERO_AddressBook_getAll_size(void* addressBook_ptr) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->getAll().size();
    DEBUG_END()
}
void* MONERO_AddressBook_getAll_byIndex(void* addressBook_ptr, int index) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->getAll()[index];
    DEBUG_END()
}
//     virtual bool addRow(const std::string &dst_addr , const std::string &payment_id, const std::string &description) = 0;
bool MONERO_AddressBook_addRow(void* addressBook_ptr, const char* dst_addr , const char* payment_id, const char* description) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->addRow(std::string(dst_addr), std::string(payment_id), std::string(description));
    DEBUG_END()
}
//     virtual bool deleteRow(std::size_t rowId) = 0;
bool MONERO_AddressBook_deleteRow(void* addressBook_ptr, size_t rowId) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->deleteRow(rowId);
    DEBUG_END()
}
//     virtual bool setDescription(std::size_t index, const std::string &description) = 0;
bool MONERO_AddressBook_setDescription(void* addressBook_ptr, size_t rowId, const char* description) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->setDescription(rowId, std::string(description));
    DEBUG_END()
}
//     virtual void refresh() = 0;
void MONERO_AddressBook_refresh(void* addressBook_ptr) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->refresh();
    DEBUG_END()
}
//     virtual std::string errorString() const = 0;
const char* MONERO_AddressBook_errorString(void* addressBook_ptr) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    std::string str = addressBook->errorString();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual int errorCode() const = 0;
int MONERO_AddressBook_errorCode(void* addressBook_ptr) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->errorCode();
    DEBUG_END()
}
//     virtual int lookupPaymentID(const std::string &payment_id) const = 0;
int MONERO_AddressBook_lookupPaymentID(void* addressBook_ptr, const char* payment_id) {
    DEBUG_START()
    Monero::AddressBook *addressBook = reinterpret_cast<Monero::AddressBook*>(addressBook_ptr);
    return addressBook->lookupPaymentID(std::string(payment_id));
    DEBUG_END()
}

// CoinsInfo
uint64_t MONERO_CoinsInfo_blockHeight(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->blockHeight();
    DEBUG_END()
}
//     virtual std::string hash() const = 0;
const char* MONERO_CoinsInfo_hash(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->hash();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual size_t internalOutputIndex() const = 0;
size_t MONERO_CoinsInfo_internalOutputIndex(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->internalOutputIndex();
    DEBUG_END()
}
//     virtual uint64_t globalOutputIndex() const = 0;
uint64_t MONERO_CoinsInfo_globalOutputIndex(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->globalOutputIndex();
    DEBUG_END()
}
//     virtual bool spent() const = 0;
bool MONERO_CoinsInfo_spent(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->spent();
    DEBUG_END()
}
//     virtual bool frozen() const = 0;
bool MONERO_CoinsInfo_frozen(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->frozen();
    DEBUG_END()
}
//     virtual uint64_t spentHeight() const = 0;
uint64_t MONERO_CoinsInfo_spentHeight(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->spentHeight();
    DEBUG_END()
}
//     virtual uint64_t amount() const = 0;
uint64_t MONERO_CoinsInfo_amount(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->amount();
    DEBUG_END()
}
//     virtual bool rct() const = 0;
bool MONERO_CoinsInfo_rct(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->rct();
    DEBUG_END()
}
//     virtual bool keyImageKnown() const = 0;
bool MONERO_CoinsInfo_keyImageKnown(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->keyImageKnown();
    DEBUG_END()
}
//     virtual size_t pkIndex() const = 0;
size_t MONERO_CoinsInfo_pkIndex(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->pkIndex();
    DEBUG_END()
}
//     virtual uint32_t subaddrIndex() const = 0;
uint32_t MONERO_CoinsInfo_subaddrIndex(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->subaddrIndex();
    DEBUG_END()
}
//     virtual uint32_t subaddrAccount() const = 0;
uint32_t MONERO_CoinsInfo_subaddrAccount(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->subaddrAccount();
    DEBUG_END()
}
//     virtual std::string address() const = 0;
const char* MONERO_CoinsInfo_address(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->address();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual std::string addressLabel() const = 0;
const char* MONERO_CoinsInfo_addressLabel(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->addressLabel();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual std::string keyImage() const = 0;
const char* MONERO_CoinsInfo_keyImage(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->keyImage();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual uint64_t unlockTime() const = 0;
uint64_t MONERO_CoinsInfo_unlockTime(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->unlockTime();
    DEBUG_END()
}
//     virtual bool unlocked() const = 0;
bool MONERO_CoinsInfo_unlocked(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->unlocked();
    DEBUG_END()
}
//     virtual std::string pubKey() const = 0;
const char* MONERO_CoinsInfo_pubKey(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->pubKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual bool coinbase() const = 0;
bool MONERO_CoinsInfo_coinbase(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    return coinsInfo->coinbase();
    DEBUG_END()
}
//     virtual std::string description() const = 0;
const char* MONERO_CoinsInfo_description(void* coinsInfo_ptr) {
    DEBUG_START()
    Monero::CoinsInfo *coinsInfo = reinterpret_cast<Monero::CoinsInfo*>(coinsInfo_ptr);
    std::string str = coinsInfo->description();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}


// coins

//     virtual ~Coins() = 0;
//     virtual int count() const = 0;
int MONERO_Coins_count(void* coins_ptr) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->count();
    DEBUG_END()
}
//     virtual CoinsInfo * coin(int index)  const = 0;
void* MONERO_Coins_coin(void* coins_ptr, int index) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->coin(index);
    DEBUG_END()
}

int MONERO_Coins_getAll_size(void* coins_ptr)  {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->getAll().size();
    DEBUG_END()
}
void* MONERO_Coins_getAll_byIndex(void* coins_ptr, int index) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->getAll()[index];
    DEBUG_END()
}

//     virtual std::vector<CoinsInfo*> getAll() const = 0;
//     virtual void refresh() = 0;
void MONERO_Coins_refresh(void* coins_ptr) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->refresh();
    DEBUG_END()
}
//     virtual void setFrozen(std::string public_key) = 0;
void MONERO_Coins_setFrozenByPublicKey(void* coins_ptr, const char* public_key) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->setFrozen(std::string(public_key));
    DEBUG_END()
}
//     virtual void setFrozen(int index) = 0;
void MONERO_Coins_setFrozen(void* coins_ptr, int index) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->setFrozen(index);
    DEBUG_END()
}
//     virtual void thaw(int index) = 0;
void MONERO_Coins_thaw(void* coins_ptr, int index) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->thaw(index);
    DEBUG_END()
}
//     virtual void thaw(std::string public_key) = 0;
void MONERO_Coins_thawByPublicKey(void* coins_ptr, const char* public_key) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->thaw(std::string(public_key));
    DEBUG_END()
}
//     virtual bool isTransferUnlocked(uint64_t unlockTime, uint64_t blockHeight) = 0;
bool MONERO_Coins_isTransferUnlocked(void* coins_ptr, uint64_t unlockTime, uint64_t blockHeight) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->isTransferUnlocked(unlockTime, blockHeight);
    DEBUG_END()
}
//    virtual void setDescription(const std::string &public_key, const std::string &description) = 0;
void MONERO_Coins_setDescription(void* coins_ptr, const char* public_key, const char* description) {
    DEBUG_START()
    Monero::Coins *coins = reinterpret_cast<Monero::Coins*>(coins_ptr);
    return coins->setDescription(std::string(public_key), std::string(description));
    DEBUG_END()
}

// SubaddressRow

//     std::string extra;
const char* MONERO_SubaddressRow_extra(void* subaddressRow_ptr) {
    DEBUG_START()
    Monero::SubaddressRow *subaddressRow = reinterpret_cast<Monero::SubaddressRow*>(subaddressRow_ptr);
    std::string str = subaddressRow->extra;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getAddress() const {return m_address;}
const char* MONERO_SubaddressRow_getAddress(void* subaddressRow_ptr) {
    DEBUG_START()
    Monero::SubaddressRow *subaddressRow = reinterpret_cast<Monero::SubaddressRow*>(subaddressRow_ptr);
    std::string str = subaddressRow->getAddress();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getLabel() const {return m_label;}
const char* MONERO_SubaddressRow_getLabel(void* subaddressRow_ptr) {
    DEBUG_START()
    Monero::SubaddressRow *subaddressRow = reinterpret_cast<Monero::SubaddressRow*>(subaddressRow_ptr);
    std::string str = subaddressRow->getLabel();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::size_t getRowId() const {return m_rowId;}
size_t MONERO_SubaddressRow_getRowId(void* subaddressRow_ptr) {
    DEBUG_START()
    Monero::SubaddressRow *subaddressRow = reinterpret_cast<Monero::SubaddressRow*>(subaddressRow_ptr);
    return subaddressRow->getRowId();
    DEBUG_END()
}

// Subaddress

int MONERO_Subaddress_getAll_size(void* subaddress_ptr) {
    DEBUG_START()
    Monero::Subaddress *subaddress = reinterpret_cast<Monero::Subaddress*>(subaddress_ptr);
    return subaddress->getAll().size();
    DEBUG_END()
}
void* MONERO_Subaddress_getAll_byIndex(void* subaddress_ptr, int index) {
    DEBUG_START()
    Monero::Subaddress *subaddress = reinterpret_cast<Monero::Subaddress*>(subaddress_ptr);
    return subaddress->getAll()[index];
    DEBUG_END()
}
//     virtual void addRow(uint32_t accountIndex, const std::string &label) = 0;
void MONERO_Subaddress_addRow(void* subaddress_ptr, uint32_t accountIndex, const char* label) {
    DEBUG_START()
    Monero::Subaddress *subaddress = reinterpret_cast<Monero::Subaddress*>(subaddress_ptr);
    return subaddress->addRow(accountIndex, std::string(label));
    DEBUG_END()
}
//     virtual void setLabel(uint32_t accountIndex, uint32_t addressIndex, const std::string &label) = 0;
void MONERO_Subaddress_setLabel(void* subaddress_ptr, uint32_t accountIndex, uint32_t addressIndex, const char* label) {
    DEBUG_START()
    Monero::Subaddress *subaddress = reinterpret_cast<Monero::Subaddress*>(subaddress_ptr);
    return subaddress->setLabel(accountIndex, addressIndex, std::string(label));
    DEBUG_END()
}
//     virtual void refresh(uint32_t accountIndex) = 0;
void MONERO_Subaddress_refresh(void* subaddress_ptr, uint32_t accountIndex) {
    DEBUG_START()
    Monero::Subaddress *subaddress = reinterpret_cast<Monero::Subaddress*>(subaddress_ptr);
    return subaddress->refresh(accountIndex);
    DEBUG_END()
}

// SubaddressAccountRow

//     std::string extra;
const char* MONERO_SubaddressAccountRow_extra(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    std::string str = subaddressAccountRow->extra;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getAddress() const {return m_address;}
const char* MONERO_SubaddressAccountRow_getAddress(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    std::string str = subaddressAccountRow->getAddress();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getLabel() const {return m_label;}
const char* MONERO_SubaddressAccountRow_getLabel(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    std::string str = subaddressAccountRow->getLabel();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getBalance() const {return m_balance;}
const char* MONERO_SubaddressAccountRow_getBalance(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    std::string str = subaddressAccountRow->getBalance();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::string getUnlockedBalance() const {return m_unlockedBalance;}
const char* MONERO_SubaddressAccountRow_getUnlockedBalance(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    std::string str = subaddressAccountRow->getUnlockedBalance();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     std::size_t getRowId() const {return m_rowId;}
size_t MONERO_SubaddressAccountRow_getRowId(void* subaddressAccountRow_ptr) {
    DEBUG_START()
    Monero::SubaddressAccountRow *subaddressAccountRow = reinterpret_cast<Monero::SubaddressAccountRow*>(subaddressAccountRow_ptr);
    return subaddressAccountRow->getRowId();
    DEBUG_END()
}

// struct SubaddressAccount
// {
//     virtual ~SubaddressAccount() = 0;
//     virtual std::vector<SubaddressAccountRow*> getAll() const = 0;
int MONERO_SubaddressAccount_getAll_size(void* subaddressAccount_ptr) {
    DEBUG_START()
    Monero::SubaddressAccount *subaddress = reinterpret_cast<Monero::SubaddressAccount*>(subaddressAccount_ptr);
    return subaddress->getAll().size();
    DEBUG_END()
}
void* MONERO_SubaddressAccount_getAll_byIndex(void* subaddressAccount_ptr, int index) {
    DEBUG_START()
    Monero::SubaddressAccount *subaddress = reinterpret_cast<Monero::SubaddressAccount*>(subaddressAccount_ptr);
    return subaddress->getAll()[index];
    DEBUG_END()
}
//     virtual void addRow(const std::string &label) = 0;
void MONERO_SubaddressAccount_addRow(void* subaddressAccount_ptr, const char* label) {
    DEBUG_START()
    Monero::SubaddressAccount *subaddress = reinterpret_cast<Monero::SubaddressAccount*>(subaddressAccount_ptr);
    return subaddress->addRow(std::string(label));
    DEBUG_END()
}
//     virtual void setLabel(uint32_t accountIndex, const std::string &label) = 0;
void MONERO_SubaddressAccount_setLabel(void* subaddressAccount_ptr, uint32_t accountIndex, const char* label) {
    DEBUG_START()
    Monero::SubaddressAccount *subaddress = reinterpret_cast<Monero::SubaddressAccount*>(subaddressAccount_ptr);
    return subaddress->setLabel(accountIndex, std::string(label));
    DEBUG_END()
}
//     virtual void refresh() = 0;
void MONERO_SubaddressAccount_refresh(void* subaddressAccount_ptr) {
    DEBUG_START()
    Monero::SubaddressAccount *subaddress = reinterpret_cast<Monero::SubaddressAccount*>(subaddressAccount_ptr);
    return subaddress->refresh();
    DEBUG_END()
}

// MultisigState

//     bool isMultisig;
bool MONERO_MultisigState_isMultisig(void* multisigState_ptr) {
    DEBUG_START()
    Monero::MultisigState *multisigState = reinterpret_cast<Monero::MultisigState*>(multisigState_ptr);
    return multisigState->isMultisig;
    DEBUG_END()
}
//     bool isReady;
bool MONERO_MultisigState_isReady(void* multisigState_ptr) {
    DEBUG_START()
    Monero::MultisigState *multisigState = reinterpret_cast<Monero::MultisigState*>(multisigState_ptr);
    return multisigState->isReady;
    DEBUG_END()
}
//     uint32_t threshold;
uint32_t MONERO_MultisigState_threshold(void* multisigState_ptr) {
    DEBUG_START()
    Monero::MultisigState *multisigState = reinterpret_cast<Monero::MultisigState*>(multisigState_ptr);
    return multisigState->threshold;
    DEBUG_END()
}
//     uint32_t total;
uint32_t MONERO_MultisigState_total(void* multisigState_ptr) {
    DEBUG_START()
    Monero::MultisigState *multisigState = reinterpret_cast<Monero::MultisigState*>(multisigState_ptr);
    return multisigState->total;
    DEBUG_END()
}

// DeviceProgress


//     virtual double progress() const { return m_progress; }
bool MONERO_DeviceProgress_progress(void* deviceProgress_ptr) {
    DEBUG_START()
    Monero::DeviceProgress *deviceProgress = reinterpret_cast<Monero::DeviceProgress*>(deviceProgress_ptr);
    return deviceProgress->progress();
    DEBUG_END()
}
//     virtual bool indeterminate() const { return m_indeterminate; }
bool MONERO_DeviceProgress_indeterminate(void* deviceProgress_ptr) {
    DEBUG_START()
    Monero::DeviceProgress *deviceProgress = reinterpret_cast<Monero::DeviceProgress*>(deviceProgress_ptr);
    return deviceProgress->indeterminate();
    DEBUG_END()
}

// Wallet

void MONERO_Wallet_delete(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    delete wallet;
    DEBUG_END()
}

const char* MONERO_Wallet_seed(void* wallet_ptr, const char* seed_offset) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->seed(std::string(seed_offset));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_getSeedLanguage(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getSeedLanguage();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

void MONERO_Wallet_setSeedLanguage(void* wallet_ptr, const char* arg) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setSeedLanguage(std::string(arg));
    DEBUG_END()
}

int MONERO_Wallet_status(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->status();
    DEBUG_END()
}

const char* MONERO_Wallet_errorString(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->errorString();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}


bool MONERO_Wallet_setPassword(void* wallet_ptr, const char* password) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setPassword(std::string(password));
    DEBUG_END()
}

const char* MONERO_Wallet_getPassword(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getPassword();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

bool MONERO_Wallet_setDevicePin(void* wallet_ptr, const char* pin) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setDevicePin(std::string(pin));
    DEBUG_END()
}

bool MONERO_Wallet_setDevicePassphrase(void* wallet_ptr, const char* passphrase) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setDevicePassphrase(std::string(passphrase));
    DEBUG_END()
}

const char* MONERO_Wallet_address(void* wallet_ptr, uint64_t accountIndex, uint64_t addressIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->address(accountIndex, addressIndex);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_path(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->path();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
int MONERO_Wallet_nettype(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->nettype();
    DEBUG_END()
}
uint8_t MONERO_Wallet_useForkRules(void* wallet_ptr, uint8_t version, int64_t early_blocks) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->useForkRules(version, early_blocks);
    DEBUG_END()
}
const char* MONERO_Wallet_integratedAddress(void* wallet_ptr, const char* payment_id) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->integratedAddress(std::string(payment_id));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_secretViewKey(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->secretViewKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_publicViewKey(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->publicViewKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_secretSpendKey(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->secretSpendKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_publicSpendKey(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->publicSpendKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
const char* MONERO_Wallet_publicMultisigSignerKey(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->publicMultisigSignerKey();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

void MONERO_Wallet_stop(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->stop();
    DEBUG_END()
}

bool MONERO_Wallet_store(void* wallet_ptr, const char* path) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->store(std::string(path));
    DEBUG_END()
}
const char* MONERO_Wallet_filename(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->filename();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
const char* MONERO_Wallet_keysFilename(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->keysFilename();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

//     virtual bool init(const std::string &daemon_address, uint64_t upper_transaction_size_limit = 0, const std::string &daemon_username = "", const std::string &daemon_password = "", bool use_ssl = false, bool lightWallet = false, const std::string &proxy_address = "") = 0;
bool MONERO_Wallet_init(void* wallet_ptr, const char* daemon_address, uint64_t upper_transaction_size_limit, const char* daemon_username, const char* daemon_password, bool use_ssl, bool lightWallet, const char* proxy_address) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->init(std::string(daemon_address), upper_transaction_size_limit, std::string(daemon_username), std::string(daemon_password), use_ssl, lightWallet, std::string(proxy_address));
    DEBUG_END()
}
bool MONERO_Wallet_createWatchOnly(void* wallet_ptr, const char* path, const char* password, const char* language) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->createWatchOnly(std::string(path), std::string(password), std::string(language));
    DEBUG_END()
}

void MONERO_Wallet_setRefreshFromBlockHeight(void* wallet_ptr, uint64_t refresh_from_block_height) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setRefreshFromBlockHeight(refresh_from_block_height);
    DEBUG_END()
}

uint64_t MONERO_Wallet_getRefreshFromBlockHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->getRefreshFromBlockHeight();
    DEBUG_END()
}

void MONERO_Wallet_setRecoveringFromSeed(void* wallet_ptr, bool recoveringFromSeed) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setRecoveringFromSeed(recoveringFromSeed);
    DEBUG_END()
}
void MONERO_Wallet_setRecoveringFromDevice(void* wallet_ptr, bool recoveringFromDevice) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setRecoveringFromDevice(recoveringFromDevice);
    DEBUG_END()
}
void MONERO_Wallet_setSubaddressLookahead(void* wallet_ptr, uint32_t major, uint32_t minor) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setSubaddressLookahead(major, minor);
    DEBUG_END()
}

bool MONERO_Wallet_connectToDaemon(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->connectToDaemon();
    DEBUG_END()
}
int MONERO_Wallet_connected(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->connected();
    DEBUG_END()
}
void MONERO_Wallet_setTrustedDaemon(void* wallet_ptr, bool arg) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setTrustedDaemon(arg);
    DEBUG_END()
}
bool MONERO_Wallet_trustedDaemon(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->trustedDaemon();
    DEBUG_END()
}
bool MONERO_Wallet_setProxy(void* wallet_ptr, const char* address) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setProxy(std::string(address));
    DEBUG_END()
}

uint64_t MONERO_Wallet_balance(void* wallet_ptr, uint32_t accountIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->balance(accountIndex);
    DEBUG_END()
}

uint64_t MONERO_Wallet_unlockedBalance(void* wallet_ptr, uint32_t accountIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->unlockedBalance(accountIndex);
    DEBUG_END()
}

uint64_t MONERO_Wallet_viewOnlyBalance(void* wallet_ptr, uint32_t accountIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->viewOnlyBalance(accountIndex);
    DEBUG_END()
}

// TODO
bool MONERO_Wallet_watchOnly(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->watchOnly();
    DEBUG_END()
}
bool MONERO_Wallet_isDeterministic(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->isDeterministic();
    DEBUG_END()
}
uint64_t MONERO_Wallet_blockChainHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->blockChainHeight();
    DEBUG_END()
}
uint64_t MONERO_Wallet_approximateBlockChainHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->approximateBlockChainHeight();
    DEBUG_END()
}
uint64_t MONERO_Wallet_estimateBlockChainHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->estimateBlockChainHeight();
    DEBUG_END()
}
uint64_t MONERO_Wallet_daemonBlockChainHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->daemonBlockChainHeight();
    DEBUG_END()
}

uint64_t MONERO_Wallet_daemonBlockChainTargetHeight(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->daemonBlockChainTargetHeight();
    DEBUG_END()
}
bool MONERO_Wallet_synchronized(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->synchronized();
    DEBUG_END()
}

const char* MONERO_Wallet_bytesToWords(const char *src) {
    DEBUG_START()
    std::string str = Monero::Wallet::bytesToWords(src);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_generateAddress(const char* seed, const char* seed_offset, uint32_t accountIndex, uint32_t addressIndex, bool testnet) {
    DEBUG_START()
    std::string str = Monero::Wallet::generateAddress(seed, seed_offset, accountIndex, addressIndex, testnet);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_generateKey(const char* seed, const char* seed_offset, const bool privateKey, const bool spendKey) {
    DEBUG_START()
    std::string str = Monero::Wallet::generateKey(seed, seed_offset, privateKey, spendKey);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_displayAmount(uint64_t amount) {
    DEBUG_START()
    std::string str = Monero::Wallet::displayAmount(amount);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

//     static uint64_t amountFromString(const std::string &amount);
uint64_t MONERO_Wallet_amountFromString(const char* amount) {
    DEBUG_START()
    return Monero::Wallet::amountFromString(amount);
    DEBUG_END()
}
//     static uint64_t amountFromDouble(double amount);
uint64_t MONERO_Wallet_amountFromDouble(double amount) {
    DEBUG_START()
    return Monero::Wallet::amountFromDouble(amount);
    DEBUG_END()
}
//     static std::string genPaymentId();
const char* MONERO_Wallet_genPaymentId() {
    DEBUG_START()
    std::string str = Monero::Wallet::genPaymentId();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     static bool paymentIdValid(const std::string &paiment_id);
bool MONERO_Wallet_paymentIdValid(const char* paiment_id) {
    DEBUG_START()
    return Monero::Wallet::paymentIdValid(std::string(paiment_id));
    DEBUG_END()
}
bool MONERO_Wallet_addressValid(const char* str, int nettype) {
    DEBUG_START()
    return Monero::Wallet::addressValid(std::string(str), static_cast<Monero::NetworkType>(nettype));
    DEBUG_END()
}

bool MONERO_Wallet_keyValid(const char* secret_key_string, const char* address_string, bool isViewKey, int nettype) {
    DEBUG_START()
    std::string error;
    return Monero::Wallet::keyValid(std::string(secret_key_string), std::string(address_string), isViewKey, static_cast<Monero::NetworkType>(nettype), error);
    DEBUG_END()
}
const char* MONERO_Wallet_keyValid_error(const char* secret_key_string, const char* address_string, bool isViewKey, int nettype)  {
    DEBUG_START()
    std::string str;
    Monero::Wallet::keyValid(std::string(secret_key_string), std::string(address_string), isViewKey, static_cast<Monero::NetworkType>(nettype), str);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()

}
const char* MONERO_Wallet_paymentIdFromAddress(const char* strarg, int nettype) {
    DEBUG_START()
    std::string str = Monero::Wallet::paymentIdFromAddress(std::string(strarg), static_cast<Monero::NetworkType>(nettype));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
uint64_t MONERO_Wallet_maximumAllowedAmount() {
    DEBUG_START()
    return Monero::Wallet::maximumAllowedAmount();
    DEBUG_END()
}

void MONERO_Wallet_init3(void* wallet_ptr, const char* argv0, const char* default_log_base_name, const char* log_path, bool console) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->init(argv0, default_log_base_name, log_path, console);
    DEBUG_END()
}
const char* MONERO_Wallet_getPolyseed(void* wallet_ptr, const char* passphrase) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string seed = "";
    std::string _passphrase = std::string(passphrase);
    wallet->getPolyseed(seed, _passphrase);
    std::string str = seed;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     static bool createPolyseed(std::string &seed_words, std::string &err, const std::string &language = "English");
const char* MONERO_Wallet_createPolyseed(const char* language) {
    DEBUG_START()
    std::string seed_words = "";
    std::string err;
    Monero::Wallet::createPolyseed(seed_words, err, std::string(language));
    std::cout << "MONERO_Wallet_createPolyseed(language: " << language << "):" << std::endl;
    std::cout << "           err: "  << err << std::endl;
    std::string str = seed_words;
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

void MONERO_Wallet_startRefresh(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->startRefresh();
    DEBUG_END()
}
void MONERO_Wallet_pauseRefresh(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->pauseRefresh();
    DEBUG_END()
}
bool MONERO_Wallet_refresh(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->refresh();
    DEBUG_END()
}
void MONERO_Wallet_refreshAsync(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->refreshAsync();
    DEBUG_END()
}
bool MONERO_Wallet_rescanBlockchain(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->rescanBlockchain();
    DEBUG_END()
}
void MONERO_Wallet_rescanBlockchainAsync(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->rescanBlockchainAsync();
    DEBUG_END()
}
void MONERO_Wallet_setAutoRefreshInterval(void* wallet_ptr, int millis) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setAutoRefreshInterval(millis);
    DEBUG_END()
}
int MONERO_Wallet_autoRefreshInterval(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->autoRefreshInterval();
    DEBUG_END()
}
void MONERO_Wallet_addSubaddressAccount(void* wallet_ptr, const char* label) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->addSubaddressAccount(std::string(label));
    DEBUG_END()
}
size_t MONERO_Wallet_numSubaddressAccounts(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->numSubaddressAccounts();
    DEBUG_END()
}
size_t MONERO_Wallet_numSubaddresses(void* wallet_ptr, uint32_t accountIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->numSubaddresses(accountIndex);
    DEBUG_END()
}
void MONERO_Wallet_addSubaddress(void* wallet_ptr, uint32_t accountIndex, const char* label) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->addSubaddress(accountIndex, std::string(label));
    DEBUG_END()
}
const char* MONERO_Wallet_getSubaddressLabel(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getSubaddressLabel(accountIndex, addressIndex);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

void MONERO_Wallet_setSubaddressLabel(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex, const char* label) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setSubaddressLabel(accountIndex, addressIndex, std::string(label));
    DEBUG_END()
}

void* MONERO_Wallet_multisig(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    Monero::MultisigState *mstate_ptr = new Monero::MultisigState(wallet->multisig());
    return reinterpret_cast<void*>(mstate_ptr);
    DEBUG_END()
}

const char* MONERO_Wallet_getMultisigInfo(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getMultisigInfo();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_makeMultisig(void* wallet_ptr, const char* info, const char* info_separator, uint32_t threshold) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->makeMultisig(splitStringVector(std::string(info), std::string(info_separator)), threshold);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_exchangeMultisigKeys(void* wallet_ptr, const char* info, const char* info_separator, bool force_update_use_with_caution) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->exchangeMultisigKeys(splitStringVector(std::string(info), std::string(info_separator)), force_update_use_with_caution);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_exportMultisigImages(void* wallet_ptr, const char* separator) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str;
    wallet->exportMultisigImages(str);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

size_t MONERO_Wallet_importMultisigImages(void* wallet_ptr, const char* info, const char* info_separator) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->importMultisigImages(splitStringVector(std::string(info), std::string(info_separator)));
    DEBUG_END()
}

size_t MONERO_Wallet_hasMultisigPartialKeyImages(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->hasMultisigPartialKeyImages();
    DEBUG_END()
}

void* MONERO_Wallet_restoreMultisigTransaction(void* wallet_ptr, const char* signData) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return reinterpret_cast<void*>(wallet->restoreMultisigTransaction(std::string(signData)));
    DEBUG_END()
}


Monero::PendingTransaction::Priority PendingTransaction_Priority_fromInt(int value) {
    switch(value) {
        case 0: return Monero::PendingTransaction::Priority::Priority_Default;
        case 1: return Monero::PendingTransaction::Priority::Priority_Low;
        case 2: return Monero::PendingTransaction::Priority::Priority_Medium;
        case 3: return Monero::PendingTransaction::Priority::Priority_High;
        default: return Monero::PendingTransaction::Priority::Priority_Default;
    }
}

void* MONERO_Wallet_createTransactionMultDest(void* wallet_ptr, const char* dst_addr_list, const char* dst_addr_list_separator, const char* payment_id,
                                              bool amount_sweep_all, const char* amount_list, const char* amount_list_separator, uint32_t mixin_count,
                                              int pendingTransactionPriority,
                                              uint32_t subaddr_account,
                                              const char* preferredInputs, const char* preferredInputs_separator) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::vector<std::string> dst_addr = splitStringVector(std::string(dst_addr_list), std::string(dst_addr_list_separator));

    Monero::optional<std::vector<uint64_t>> optAmount;
    if (!amount_sweep_all) {
        optAmount = splitStringUint(std::string(amount_list), std::string(amount_list_separator));;
    }
    std::set<uint32_t> subaddr_indices = {};
    std::set<std::string> preferred_inputs = splitString(std::string(preferredInputs), std::string(preferredInputs_separator));

    return wallet->createTransactionMultDest(
                                             dst_addr, std::string(payment_id),
                                             optAmount, mixin_count,
                                             PendingTransaction_Priority_fromInt(pendingTransactionPriority),
                                             subaddr_account,
                                             subaddr_indices,
                                             preferred_inputs
                                             );
    DEBUG_END()
}

void* MONERO_Wallet_createTransaction(void* wallet_ptr, const char* dst_addr, const char* payment_id,
                                      uint64_t amount, uint32_t mixin_count,
                                      int pendingTransactionPriority,
                                      uint32_t subaddr_account,
                                      const char* preferredInputs, const char* separator) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    Monero::optional<uint64_t> optAmount;
    if (amount != 0) {
        optAmount = amount;
    }
    std::set<uint32_t> subaddr_indices = {};
    std::set<std::string> preferred_inputs = splitString(std::string(preferredInputs), std::string(separator));
    return wallet->createTransaction(std::string(dst_addr), std::string(payment_id),
                                     optAmount, mixin_count,
                                     PendingTransaction_Priority_fromInt(pendingTransactionPriority),
                                     subaddr_account, subaddr_indices, preferred_inputs);
    DEBUG_END()
}

void MONERO_Wallet_disposeTransaction(void* wallet_ptr, void* pendingTx_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    Monero::PendingTransaction *pendingTx = reinterpret_cast<Monero::PendingTransaction*>(pendingTx_ptr);
    wallet->disposeTransaction(pendingTx);
    DEBUG_END()
}

uint64_t MONERO_Wallet_estimateTransactionFee(void* wallet_ptr, const char* dst_addr_list, const char* dst_addr_list_separator, const char* amount_list, const char* amount_list_separator, int priority) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);

    if (!dst_addr_list || !amount_list) {
        return 0;
    }

    std::vector<std::string> addresses;
    const std::string addr_sep(dst_addr_list_separator ? dst_addr_list_separator : "");
    if (addr_sep.empty()) {
        addresses.push_back(std::string(dst_addr_list));
    } else {
        addresses = splitStringVector(std::string(dst_addr_list), addr_sep);
    }

    std::vector<uint64_t> amounts;
    const std::string amount_sep(amount_list_separator ? amount_list_separator : "");
    if (amount_sep.empty()) {
        amounts.push_back(Monero::Wallet::amountFromString(std::string(amount_list)));
    } else {
        amounts = splitStringUint(std::string(amount_list), amount_sep);
    }

    if (addresses.size() != amounts.size()) {
        return 0;
    }

    std::vector<std::pair<std::string, uint64_t>> destinations;
    for (size_t i = 0; i < addresses.size(); ++i) {
        destinations.push_back(std::make_pair(addresses[i], amounts[i]));
    }
    return wallet->estimateTransactionFee(destinations, PendingTransaction_Priority_fromInt(priority));
    DEBUG_END()
}

void* MONERO_Wallet_loadUnsignedTx(void* wallet_ptr, const char* fileName) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->loadUnsignedTx(std::string(fileName));
    DEBUG_END()
}

void* MONERO_Wallet_loadUnsignedTxUR(void* wallet_ptr, const char* input) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->loadUnsignedTxUR(std::string(input));
    DEBUG_END()
}
bool MONERO_Wallet_submitTransaction(void* wallet_ptr, const char* fileName) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->submitTransaction(std::string(fileName));
    DEBUG_END()
}
bool MONERO_Wallet_submitTransactionUR(void* wallet_ptr, const char* input) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->submitTransactionUR(std::string(input));
    DEBUG_END()
}
bool MONERO_Wallet_hasUnknownKeyImages(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->hasUnknownKeyImages();
    DEBUG_END()
}
bool MONERO_Wallet_exportKeyImages(void* wallet_ptr, const char* filename, bool all) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->exportKeyImages(std::string(filename), all);
    DEBUG_END()
}

const char* MONERO_Wallet_exportKeyImagesUR(void* wallet_ptr, size_t max_fragment_length, bool all) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->exportKeyImagesUR(max_fragment_length, all);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
bool MONERO_Wallet_importKeyImages(void* wallet_ptr, const char* filename) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->importKeyImages(std::string(filename));
    DEBUG_END()
}
bool MONERO_Wallet_importKeyImagesUR(void* wallet_ptr, const char* input) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->importKeyImagesUR(std::string(input));
    DEBUG_END()
}
bool MONERO_Wallet_exportOutputs(void* wallet_ptr, const char* filename, bool all) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->exportOutputs(std::string(filename), all);
    DEBUG_END()
}
const char* MONERO_Wallet_exportOutputsUR(void* wallet_ptr, size_t max_fragment_length, bool all) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->exportOutputsUR(max_fragment_length, all);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
bool MONERO_Wallet_importOutputs(void* wallet_ptr, const char* filename) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->importOutputs(std::string(filename));
    DEBUG_END()
}
bool MONERO_Wallet_importOutputsUR(void* wallet_ptr, const char* input) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->importOutputsUR(std::string(input));
    DEBUG_END()
}
//     virtual bool setupBackgroundSync(const BackgroundSyncType background_sync_type, const std::string &wallet_password, const optional<std::string> &background_cache_password) = 0;
bool MONERO_Wallet_setupBackgroundSync(void* wallet_ptr, int background_sync_type, const char* wallet_password, const char* background_cache_password) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setupBackgroundSync(Monero::Wallet::BackgroundSyncType::BackgroundSync_CustomPassword, std::string(wallet_password), std::string(background_cache_password));
    DEBUG_END()
}
//     virtual BackgroundSyncType getBackgroundSyncType() const = 0;
int MONERO_Wallet_getBackgroundSyncType(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->getBackgroundSyncType();
    DEBUG_END()
}
//     virtual bool startBackgroundSync() = 0;
bool MONERO_Wallet_startBackgroundSync(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->startBackgroundSync();
    DEBUG_END()
}
//     virtual bool stopBackgroundSync(const std::string &wallet_password) = 0;
bool MONERO_Wallet_stopBackgroundSync(void* wallet_ptr, const char* wallet_password) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->stopBackgroundSync(std::string(wallet_password));
    DEBUG_END()
}
//     virtual bool isBackgroundSyncing() const = 0;
bool MONERO_Wallet_isBackgroundSyncing(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->hasUnknownKeyImages();
    DEBUG_END()
}
//     virtual bool isBackgroundWallet() const = 0;
bool MONERO_Wallet_isBackgroundWallet(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->isBackgroundWallet();
    DEBUG_END()
}
void* MONERO_Wallet_history(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->history();
    DEBUG_END()
}
void* MONERO_Wallet_addressBook(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->addressBook();
    DEBUG_END()
}
//     virtual Coins * coins() = 0;
void* MONERO_Wallet_coins(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->coins();
    DEBUG_END()
}
//     virtual Subaddress * subaddress() = 0;
void* MONERO_Wallet_subaddress(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->subaddress();
    DEBUG_END()
}
//     virtual SubaddressAccount * subaddressAccount() = 0;
void* MONERO_Wallet_subaddressAccount(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->subaddressAccount();
    DEBUG_END()
}
//     virtual uint32_t defaultMixin() const = 0;
uint32_t MONERO_Wallet_defaultMixin(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->defaultMixin();
    DEBUG_END()
}
//     virtual void setDefaultMixin(uint32_t arg) = 0;
void MONERO_Wallet_setDefaultMixin(void* wallet_ptr, uint32_t arg) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setDefaultMixin(arg);
    DEBUG_END()
}
//     virtual bool setCacheAttribute(const std::string &key, const std::string &val) = 0;
bool MONERO_Wallet_setCacheAttribute(void* wallet_ptr, const char* key, const char* val) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setCacheAttribute(std::string(key), std::string(val));
    DEBUG_END()
}
//     virtual std::string getCacheAttribute(const std::string &key) const = 0;
const char* MONERO_Wallet_getCacheAttribute(void* wallet_ptr, const char* key) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getCacheAttribute(std::string(key));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual bool setUserNote(const std::string &txid, const std::string &note) = 0;
bool MONERO_Wallet_setUserNote(void* wallet_ptr, const char* txid, const char* note) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setUserNote(std::string(txid), std::string(note));
    DEBUG_END()
}
//     virtual std::string getUserNote(const std::string &txid) const = 0;
const char* MONERO_Wallet_getUserNote(void* wallet_ptr, const char* txid) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getUserNote(std::string(txid));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_getTxKey(void* wallet_ptr, const char* txid) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->getTxKey(std::string(txid));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

const char* MONERO_Wallet_signMessage(void* wallet_ptr, const char* message, const char* address) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = wallet->signMessage(std::string(message), std::string(address));
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

bool MONERO_Wallet_verifySignedMessage(void* wallet_ptr, const char* message, const char* address, const char* signature) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    bool v = wallet->verifySignedMessage(std::string(message), std::string(address), std::string(signature));
    return v;
    DEBUG_END()
}

bool MONERO_Wallet_rescanSpent(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->rescanSpent();
    DEBUG_END()
}

void MONERO_Wallet_setOffline(void* wallet_ptr, bool offline) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->setOffline(offline);
    DEBUG_END()
}
//     virtual bool isOffline() const = 0;
bool MONERO_Wallet_isOffline(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->isOffline();
    DEBUG_END()
}

void MONERO_Wallet_segregatePreForkOutputs(void* wallet_ptr, bool segregate) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->segregatePreForkOutputs(segregate);
    DEBUG_END()
}
//     virtual void segregationHeight(uint64_t height) = 0;
void MONERO_Wallet_segregationHeight(void* wallet_ptr, uint64_t height) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->segregationHeight(height);
    DEBUG_END()
}
//     virtual void keyReuseMitigation2(bool mitigation) = 0;
void MONERO_Wallet_keyReuseMitigation2(void* wallet_ptr, bool mitigation) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->keyReuseMitigation2(mitigation);
    DEBUG_END()
}
//     virtual bool lightWalletLogin(bool &isNewWallet) const = 0;
//     virtual bool lightWalletImportWalletRequest(std::string &payment_id, uint64_t &fee, bool &new_request, bool &request_fulfilled, std::string &payment_address, std::string &status) = 0;
//     virtual bool lockKeysFile() = 0;
bool MONERO_Wallet_lockKeysFile(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->lockKeysFile();
    DEBUG_END()
}
//     virtual bool unlockKeysFile() = 0;
bool MONERO_Wallet_unlockKeysFile(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->unlockKeysFile();
    DEBUG_END()
}
//     virtual bool isKeysFileLocked() = 0;
bool MONERO_Wallet_isKeysFileLocked(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->isKeysFileLocked();
    DEBUG_END()
}
//     virtual Device getDeviceType() const = 0;
int MONERO_Wallet_getDeviceType(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->getDeviceType();
    DEBUG_END()
}
//     virtual uint64_t coldKeyImageSync(uint64_t &spent, uint64_t &unspent) = 0;
uint64_t MONERO_Wallet_coldKeyImageSync(void* wallet_ptr, uint64_t spent, uint64_t unspent) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->coldKeyImageSync(spent, unspent);
    DEBUG_END()
}
//     virtual void deviceShowAddress(uint32_t accountIndex, uint32_t addressIndex, const std::string &paymentId) = 0;
const char* MONERO_Wallet_deviceShowAddress(void* wallet_ptr, uint32_t accountIndex, uint32_t addressIndex) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    std::string str = "";
    wallet->deviceShowAddress(accountIndex, addressIndex, str);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}
//     virtual bool reconnectDevice() = 0;
bool MONERO_Wallet_reconnectDevice(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->reconnectDevice();
    DEBUG_END()
};

uint64_t MONERO_Wallet_getBytesReceived(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->getBytesReceived();
    DEBUG_END()
}
uint64_t MONERO_Wallet_getBytesSent(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wallet->getBytesSent();
    DEBUG_END()
}

bool MONERO_Wallet_getStateIsConnected() {
    DEBUG_START()
    return Monero::Wallet::getStateIsConnected();
    DEBUG_END()
}

unsigned char* MONERO_Wallet_getSendToDevice() {
    DEBUG_START()
    return Monero::Wallet::getSendToDevice();
    DEBUG_END()
}

size_t MONERO_Wallet_getSendToDeviceLength() {
    DEBUG_START()
    return Monero::Wallet::getSendToDeviceLength();
    DEBUG_END()
}

unsigned char* MONERO_Wallet_getReceivedFromDevice() {
    DEBUG_START()
    return Monero::Wallet::getReceivedFromDevice();
    DEBUG_END()
}

size_t MONERO_Wallet_getReceivedFromDeviceLength() {
    DEBUG_START()
    return Monero::Wallet::getReceivedFromDeviceLength();
    DEBUG_END()
}

bool MONERO_Wallet_getWaitsForDeviceSend() {
    DEBUG_START()
    return Monero::Wallet::getWaitsForDeviceSend();
    DEBUG_END()
}

bool MONERO_Wallet_getWaitsForDeviceReceive() {
    DEBUG_START()
    return Monero::Wallet::getWaitsForDeviceReceive();
    DEBUG_END()
}

void MONERO_Wallet_setDeviceReceivedData(unsigned char* data, size_t len) {
    DEBUG_START()
    Monero::Wallet::setDeviceReceivedData(data, len);
    DEBUG_END()
}

void MONERO_Wallet_setDeviceSendData(unsigned char* data, size_t len) {
    DEBUG_START()
    Monero::Wallet::setDeviceSendData(data, len);
    DEBUG_END()
}

void MONERO_Wallet_setLedgerCallback(void (*sendToLedgerDevice)(unsigned char *command, unsigned int cmd_len)) {
    DEBUG_START()
    Monero::Wallet::setLedgerCallback(sendToLedgerDevice);
    DEBUG_END()
}

void* MONERO_WalletManager_createWallet(void* wm_ptr, const char* path, const char* password, const char* language, int networkType) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = wm->createWallet(
                                              std::string(path),
                                              std::string(password),
                                              std::string(language),
                                              static_cast<Monero::NetworkType>(networkType));
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}

void* MONERO_WalletManager_openWallet(void* wm_ptr, const char* path, const char* password, int networkType) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = wm->openWallet(
                                            std::string(path),
                                            std::string(password),
                                            static_cast<Monero::NetworkType>(networkType));
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}
void* MONERO_WalletManager_recoveryWallet(void* wm_ptr, const char* path, const char* password, const char* mnemonic, int networkType, uint64_t restoreHeight, uint64_t kdfRounds, const char* seedOffset) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    // (const std::string &path, const std::string &password, const std::string &mnemonic,
    //                                     NetworkType nettype = MAINNET, uint64_t restoreHeight = 0, uint64_t kdf_rounds = 1,
    //                                     const std::string &seed_offset = {})
    Monero::Wallet *wallet = wm->recoveryWallet(
                                                std::string(path),
                                                std::string(password),
                                                std::string(mnemonic),
                                                static_cast<Monero::NetworkType>(networkType),
                                                restoreHeight,
                                                kdfRounds,
                                                std::string(seedOffset));
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}
//     virtual Wallet * createWalletFromKeys(const std::string &path,
//                                                     const std::string &password,
//                                                     const std::string &language,
//                                                     NetworkType nettype,
//                                                     uint64_t restoreHeight,
//                                                     const std::string &addressString,
//                                                     const std::string &viewKeyString,
//                                                     const std::string &spendKeyString = "",
//                                                     uint64_t kdf_rounds = 1) = 0;
void* MONERO_WalletManager_createWalletFromKeys(void* wm_ptr, const char* path, const char* password, const char* language, int nettype, uint64_t restoreHeight, const char* addressString, const char* viewKeyString, const char* spendKeyString, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = wm->createWalletFromKeys(
                                                      std::string(path),
                                                      std::string(password),
                                                      std::string(language),
                                                      static_cast<Monero::NetworkType>(nettype),
                                                      restoreHeight,
                                                      std::string(addressString),
                                                      std::string(viewKeyString),
                                                      std::string(spendKeyString));
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}

void* MONERO_WalletManager_createWalletFromDevice(void* wm_ptr, const char* path, const char* password, int nettype, const char* deviceName, uint64_t restoreHeight, const char* subaddressLookahead, const char* viewKeyString, const char* spendKeyString, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = wm->createWalletFromDevice(std::string(path),
                                                        std::string(password),
                                                        static_cast<Monero::NetworkType>(nettype),
                                                        std::string(deviceName),
                                                        restoreHeight,
                                                        std::string(subaddressLookahead),
                                                        kdf_rounds);
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}

void* MONERO_WalletManager_createDeterministicWalletFromSpendKey(void* wm_ptr, const char* path, const char* password,
                                                                 const char* language, int nettype, uint64_t restoreHeight,
                                                                 const char* spendKeyString, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = wm->createDeterministicWalletFromSpendKey(
                                                                       std::string(path),
                                                                       std::string(password),
                                                                       std::string(language),
                                                                       static_cast<Monero::NetworkType>(nettype),
                                                                       restoreHeight,
                                                                       std::string(spendKeyString),
                                                                       kdf_rounds
                                                                       );
    return reinterpret_cast<void*>(wallet);
    DEBUG_END()
}

void* MONERO_WalletManager_createWalletFromPolyseed(void* wm_ptr, const char* path, const char* password,
                                                    int nettype, const char* mnemonic, const char* passphrase,
                                                    bool newWallet, uint64_t restore_height, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->createWalletFromPolyseed(std::string(path),
                                        std::string(password),
                                        static_cast<Monero::NetworkType>(nettype),
                                        std::string(mnemonic),
                                        std::string(passphrase),
                                        newWallet,
                                        restore_height,
                                        kdf_rounds);
    DEBUG_END()
}


bool MONERO_WalletManager_closeWallet(void* wm_ptr, void* wallet_ptr, bool store) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return wm->closeWallet(wallet, store);
    DEBUG_END()
}

bool MONERO_WalletManager_walletExists(void* wm_ptr, const char* path) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->walletExists(std::string(path));
    DEBUG_END()
}

//     virtual bool verifyWalletPassword(const std::string &keys_file_name, const std::string &password, bool no_spend_key, uint64_t kdf_rounds = 1) const = 0;
bool MONERO_WalletManager_verifyWalletPassword(void* wm_ptr, const char* keys_file_name, const char* password, bool no_spend_key, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->verifyWalletPassword(std::string(keys_file_name), std::string(password), no_spend_key, kdf_rounds);
    DEBUG_END()
}

//     virtual bool queryWalletDevice(Wallet::Device& device_type, const std::string &keys_file_name, const std::string &password, uint64_t kdf_rounds = 1) const = 0;
int MONERO_WalletManager_queryWalletDevice(void* wm_ptr, const char* keys_file_name, const char* password, uint64_t kdf_rounds) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    Monero::Wallet::Device device_type;
    wm->queryWalletDevice(device_type, std::string(keys_file_name), std::string(password), kdf_rounds);
    return device_type;
    DEBUG_END()
}

//     virtual std::vector<std::string> findWallets(const std::string &path) = 0;
const char* MONERO_WalletManager_findWallets(void* wm_ptr, const char* path, const char* separator) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return vectorToString(wm->findWallets(std::string(path)), std::string(separator));
    DEBUG_END()
}


const char* MONERO_WalletManager_errorString(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    std::string str = wm->errorString();
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

void MONERO_WalletManager_setDaemonAddress(void* wm_ptr, const char* address) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->setDaemonAddress(std::string(address));
    DEBUG_END()
}

bool MONERO_WalletManager_setProxy(void* wm_ptr, const char* address) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->setProxy(std::string(address));
    DEBUG_END()
}


//     virtual bool connected(uint32_t *version = NULL) = 0;
//     virtual uint64_t blockchainHeight() = 0;
uint64_t MONERO_WalletManager_blockchainHeight(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->blockchainHeight();
    DEBUG_END()
}
//     virtual uint64_t blockchainTargetHeight() = 0;
uint64_t MONERO_WalletManager_blockchainTargetHeight(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->blockchainTargetHeight();
    DEBUG_END()
}
//     virtual uint64_t networkDifficulty() = 0;
uint64_t MONERO_WalletManager_networkDifficulty(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->networkDifficulty();
    DEBUG_END()
}
//     virtual double miningHashRate() = 0;
double MONERO_WalletManager_miningHashRate(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->miningHashRate();
    DEBUG_END()
}
//     virtual uint64_t blockTarget() = 0;
uint64_t MONERO_WalletManager_blockTarget(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->blockTarget();
    DEBUG_END()
}
//     virtual bool isMining() = 0;
bool MONERO_WalletManager_isMining(void* wm_ptr) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->isMining();
    DEBUG_END()
}
//     virtual bool startMining(const std::string &address, uint32_t threads = 1, bool background_mining = false, bool ignore_battery = true) = 0;
bool MONERO_WalletManager_startMining(void* wm_ptr, const char* address, uint32_t threads, bool backgroundMining, bool ignoreBattery) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->startMining(std::string(address), threads, backgroundMining, ignoreBattery);
    DEBUG_END()
}
//     virtual bool stopMining() = 0;
bool MONERO_WalletManager_stopMining(void* wm_ptr, const char* address) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    return wm->stopMining();
    DEBUG_END()
}
//     virtual std::string resolveOpenAlias(const std::string &address, bool &dnssec_valid) const = 0;
const char* MONERO_WalletManager_resolveOpenAlias(void* wm_ptr, const char* address, bool dnssec_valid) {
    DEBUG_START()
    Monero::WalletManager *wm = reinterpret_cast<Monero::WalletManager*>(wm_ptr);
    std::string str = wm->resolveOpenAlias(std::string(address), dnssec_valid);
    const std::string::size_type size = str.size();
    char *buffer = new char[size + 1];   //we need extra char for NUL
    memcpy(buffer, str.c_str(), size + 1);
    return buffer;
    DEBUG_END()
}

// WalletManagerFactory

void* MONERO_WalletManagerFactory_getWalletManager() {
    DEBUG_START()
    Monero::WalletManager *wm = Monero::WalletManagerFactory::getWalletManager();
    return reinterpret_cast<void*>(wm);
    DEBUG_END()
}

void MONERO_WalletManagerFactory_setLogLevel(int level) {
    DEBUG_START()
    return Monero::WalletManagerFactory::setLogLevel(level);
    DEBUG_END()
}

void MONERO_WalletManagerFactory_setLogCategories(const char* categories) {
    DEBUG_START()
    return Monero::WalletManagerFactory::setLogCategories(std::string(categories));
    DEBUG_END()
}

// DEBUG functions

// As it turns out we need a bit more functions to make sure that the library is working.
// 0) void
// 1) bool
// 2) int
// 3) uint64_t
// 4) void*
// 5) const char*

void MONERO_DEBUG_test0() {
    return;
}

bool MONERO_DEBUG_test1(bool x) {
    return x;
}

int MONERO_DEBUG_test2(int x) {
    return x;
}

uint64_t MONERO_DEBUG_test3(uint64_t x) {
    return x;
}

void* MONERO_DEBUG_test4(uint64_t x) {
    int *y = new int(x);
    return reinterpret_cast<void*>(y);
}

const char* MONERO_DEBUG_test5() {
    const char *text = "This is a const char* text";
    return text;
}

const char* MONERO_DEBUG_test5_std() {
    std::string text("This is a std::string text");
    const char *text2 = "This is a text";
    return text2;
}

bool MONERO_DEBUG_isPointerNull(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    return (wallet != NULL);
    DEBUG_END()
}

// cake wallet world
// TODO(mrcyjanek): https://api.dart.dev/stable/3.3.3/dart-ffi/Pointer/fromFunction.html
//                  callback to dart should be possible..? I mean why not? But I need to
//                  wait for other implementation (Go preferably) to see if this approach
//                  will work as expected.
struct MONERO_cw_WalletListener;
struct MONERO_cw_WalletListener : Monero::WalletListener
{
    uint64_t m_height;
    bool m_need_to_refresh;
    bool m_new_transaction;

    MONERO_cw_WalletListener()
    {
        m_height = 0;
        m_need_to_refresh = false;
        m_new_transaction = false;
    }

    void moneySpent(const std::string &txId, uint64_t amount)
    {
        m_new_transaction = true;
    }

    void moneyReceived(const std::string &txId, uint64_t amount)
    {
        m_new_transaction = true;
    }

    void unconfirmedMoneyReceived(const std::string &txId, uint64_t amount)
    {
        m_new_transaction = true;
    }

    void newBlock(uint64_t height)
    {
        m_height = height;
    }

    void updated()
    {
        m_new_transaction = true;
    }

    void refreshed()
    {
        m_need_to_refresh = true;
    }


    void cw_resetNeedToRefresh()
    {
        m_need_to_refresh = false;
    }

    bool cw_isNeedToRefresh()
    {
        return m_need_to_refresh;
    }

    bool cw_isNewTransactionExist()
    {
        return m_new_transaction;
    }

    void cw_resetIsNewTransactionExist()
    {
        m_new_transaction = false;
    }

    uint64_t cw_height()
    {
        return m_height;
    }
};

void* MONERO_cw_getWalletListener(void* wallet_ptr) {
    DEBUG_START()
    Monero::Wallet *wallet = reinterpret_cast<Monero::Wallet*>(wallet_ptr);
    MONERO_cw_WalletListener *listener = new MONERO_cw_WalletListener();
    wallet->setListener(listener);
    return reinterpret_cast<void*>(listener);
    DEBUG_END()
}

void MONERO_cw_WalletListener_resetNeedToRefresh(void* cw_walletListener_ptr) {
    DEBUG_START()
    MONERO_cw_WalletListener *listener = reinterpret_cast<MONERO_cw_WalletListener*>(cw_walletListener_ptr);
    listener->cw_resetNeedToRefresh();
    DEBUG_END()
}

bool MONERO_cw_WalletListener_isNeedToRefresh(void* cw_walletListener_ptr) {
    DEBUG_START()
    MONERO_cw_WalletListener *listener = reinterpret_cast<MONERO_cw_WalletListener*>(cw_walletListener_ptr);
    return listener->cw_isNeedToRefresh();
    DEBUG_END()
};

bool MONERO_cw_WalletListener_isNewTransactionExist(void* cw_walletListener_ptr) {
    DEBUG_START()
    MONERO_cw_WalletListener *listener = reinterpret_cast<MONERO_cw_WalletListener*>(cw_walletListener_ptr);
    return listener->cw_isNewTransactionExist();
    DEBUG_END()
};

void MONERO_cw_WalletListener_resetIsNewTransactionExist(void* cw_walletListener_ptr) {
    DEBUG_START()
    MONERO_cw_WalletListener *listener = reinterpret_cast<MONERO_cw_WalletListener*>(cw_walletListener_ptr);
    listener->cw_resetIsNewTransactionExist();
    DEBUG_END()
};

uint64_t MONERO_cw_WalletListener_height(void* cw_walletListener_ptr) {
    DEBUG_START()
    MONERO_cw_WalletListener *listener = reinterpret_cast<MONERO_cw_WalletListener*>(cw_walletListener_ptr);
    return listener->cw_height();
    DEBUG_END()
};

const char* MONERO_checksum_wallet2_api_c_h() {
    return MONERO_wallet2_api_c_h_sha256;
}
const char* MONERO_checksum_wallet2_api_c_cpp() {
    return MONERO_wallet2_api_c_cpp_sha256;
}
const char* MONERO_checksum_wallet2_api_c_exp() {
    return MONERO_wallet2_api_c_exp_sha256;
}
// i hate windows

void MONERO_free(void* ptr) {
    delete[] static_cast<char*>(ptr);
}

// Defined in monero's generated src/version.cpp, linked in via libversion.a. Declared here
// rather than #include "version.h" because that header is generated into the monero build
// tree and is not shipped with the prebuilt xcframework.
extern const char* const MONERO_VERSION_FULL;
extern const char* const MONERO_VERSION;

const char* MONERO_VERSION_getFull() {
    return MONERO_VERSION_FULL;
}

const char* MONERO_VERSION_getShort() {
    return MONERO_VERSION;
}

#ifdef __cplusplus
}
#endif
