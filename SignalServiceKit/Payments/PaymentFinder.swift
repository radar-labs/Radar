//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class PaymentFinder {

    public class func paymentModels(
        paymentStates: [TSPaymentState],
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let paymentStatesToLookup = paymentStates.compactMap { $0.rawValue }.map { "\($0)" }.joined(separator: ",")

        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .paymentState) IN (\(paymentStatesToLookup))
        """

        return fetchAll(sql: sql, arguments: [], tx: transaction)
    }

    public class func firstUnreadPaymentModel(transaction: DBReadTransaction) -> TSPaymentModel? {
        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        LIMIT 1
        """
        return TSPaymentModel.anyFetch(
            sql: sql,
            arguments: [],
            transaction: transaction,
        )
    }

    public class func allUnreadPaymentModels(transaction: DBReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        """
        return fetchAll(sql: sql, arguments: [], tx: transaction)
    }

    public class func unreadCount(transaction: DBReadTransaction) -> UInt {
        return failIfThrows {
            return try UInt.fetchOne(
                transaction.database,
                sql: """
                SELECT COUNT(*)
                FROM \(TSPaymentModel.databaseTableName)
                WHERE \(paymentModelColumn: .isUnread) = 1
                """,
                arguments: [],
            )!
        }
    }

    public class func paymentModels(
        forMcLedgerBlockIndex mcLedgerBlockIndex: UInt64,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .mcLedgerBlockIndex) = ?
        """
        return fetchAll(sql: sql, arguments: [mcLedgerBlockIndex], tx: transaction)
    }

    public class func paymentModels(
        forMcReceiptData mcReceiptData: Data,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .mcReceiptData) = ?
        """
        return fetchAll(sql: sql, arguments: [mcReceiptData], tx: transaction)
    }

    public class func paymentModels(
        forMcTransactionData mcTransactionData: Data,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(TSPaymentModel.databaseTableName)
        WHERE \(paymentModelColumn: .mcTransactionData) = ?
        """
        return fetchAll(sql: sql, arguments: [mcTransactionData], tx: transaction)
    }

    private static func fetchAll(sql: String, arguments: StatementArguments, tx: DBReadTransaction) -> [TSPaymentModel] {
        var results = [TSPaymentModel]()
        TSPaymentModel.anyEnumerate(
            transaction: tx,
            sql: sql,
            arguments: arguments,
            block: { paymentModel, _ in
                results.append(paymentModel)
            },
        )
        return results
    }
}
