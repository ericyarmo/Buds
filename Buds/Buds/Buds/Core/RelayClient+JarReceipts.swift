/**
 * RelayClient + Jar Receipts (Phase 10.3 Module 1)
 *
 * Integration with relay for jar receipt storage and backfill.
 *
 * CRITICAL ARCHITECTURE:
 * - Client sends receipt WITHOUT sequence → relay assigns authoritative sequence
 * - Relay returns { receipt_cid, sequence_number, jar_id }
 * - Client stores relay-assigned sequence locally
 */

import Foundation

extension RelayClient {

    // MARK: - Store Jar Receipt

    /**
     * POST /api/jars/{jar_id}/receipts
     *
     * Send jar receipt to relay → relay assigns sequence number
     *
     * Request:
     * {
     *   "receipt_data": "base64...",    // Signed CBOR payload (NO sequence inside)
     *   "signature": "base64...",       // Ed25519 signature over receipt_data
     *   "parent_cid": "bafy..."         // Optional (causal metadata)
     * }
     *
     * Response:
     * {
     *   "success": true,
     *   "receipt_cid": "bafy...",
     *   "sequence_number": 5,           // AUTHORITATIVE (relay-assigned)
     *   "jar_id": "uuid"
     * }
     */
    func storeJarReceipt(
        jarID: String,
        receiptData: Data,
        signature: Data,
        parentCID: String?
    ) async throws -> StoreReceiptResponse {
        let endpoint = "\(baseURL)/api/jars/\(jarID)/receipts"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add Firebase auth token
        if let token = try? await getFirebaseToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode request body
        var body: [String: Any] = [
            "receipt_data": receiptData.base64EncodedString(),
            "signature": signature.base64EncodedString()
        ]

        if let parentCID = parentCID {
            body["parent_cid"] = parentCID
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RelayError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StoreReceiptResponse.self, from: data)
    }

    // MARK: - Get Jar Receipts (Backfill)

    /**
     * GET /api/jars/{jar_id}/receipts?after={seq}&limit={N}
     *
     * Normal sync: Get all receipts after last sequence
     *
     * Response:
     * {
     *   "receipts": [
     *     {
     *       "jar_id": "uuid",
     *       "sequence_number": 5,
     *       "receipt_cid": "bafy...",
     *       "receipt_data": "base64...",
     *       "signature": "base64...",
     *       "sender_did": "did:phone:...",
     *       "received_at": 1234567890,
     *       "parent_cid": "bafy..."
     *     }
     *   ]
     * }
     */
    func getJarReceipts(
        jarID: String,
        after lastSequence: Int,
        limit: Int = 500
    ) async throws -> [RelayEnvelope] {
        let endpoint = "\(baseURL)/api/jars/\(jarID)/receipts?after=\(lastSequence)&limit=\(limit)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"

        // Add Firebase auth token
        if let token = try? await getFirebaseToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RelayError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Decode response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let receiptsArray = json?["receipts"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        // Parse each receipt envelope
        return try receiptsArray.map { receiptDict in
            guard let jarID = receiptDict["jar_id"] as? String,
                  let sequenceNumber = receiptDict["sequence_number"] as? Int,
                  let receiptCID = receiptDict["receipt_cid"] as? String,
                  let receiptDataBase64 = receiptDict["receipt_data"] as? String,
                  let signatureBase64 = receiptDict["signature"] as? String,
                  let senderDID = receiptDict["sender_did"] as? String,
                  let receivedAt = receiptDict["received_at"] as? Int64 else {
                throw RelayError.invalidResponse
            }

            guard let receiptData = Data(base64Encoded: receiptDataBase64),
                  let signature = Data(base64Encoded: signatureBase64) else {
                throw RelayError.invalidResponse
            }

            let parentCID = receiptDict["parent_cid"] as? String

            return RelayEnvelope(
                jarID: jarID,
                sequenceNumber: sequenceNumber,
                receiptCID: receiptCID,
                receiptData: receiptData,
                signature: signature,
                senderDID: senderDID,
                receivedAt: receivedAt,
                parentCID: parentCID
            )
        }
    }

    /**
     * GET /api/jars/{jar_id}/receipts?from={seq}&to={seq}
     *
     * Gap filling: Get specific range of receipts
     */
    func getJarReceipts(
        jarID: String,
        from fromSeq: Int,
        to toSeq: Int
    ) async throws -> [RelayEnvelope] {
        let endpoint = "\(baseURL)/api/jars/\(jarID)/receipts?from=\(fromSeq)&to=\(toSeq)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"

        // Add Firebase auth token
        if let token = try? await getFirebaseToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RelayError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Decode response (same format as after API)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let receiptsArray = json?["receipts"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        // Parse each receipt envelope
        return try receiptsArray.map { receiptDict in
            guard let jarID = receiptDict["jar_id"] as? String,
                  let sequenceNumber = receiptDict["sequence_number"] as? Int,
                  let receiptCID = receiptDict["receipt_cid"] as? String,
                  let receiptDataBase64 = receiptDict["receipt_data"] as? String,
                  let signatureBase64 = receiptDict["signature"] as? String,
                  let senderDID = receiptDict["sender_did"] as? String,
                  let receivedAt = receiptDict["received_at"] as? Int64 else {
                throw RelayError.invalidResponse
            }

            guard let receiptData = Data(base64Encoded: receiptDataBase64),
                  let signature = Data(base64Encoded: signatureBase64) else {
                throw RelayError.invalidResponse
            }

            let parentCID = receiptDict["parent_cid"] as? String

            return RelayEnvelope(
                jarID: jarID,
                sequenceNumber: sequenceNumber,
                receiptCID: receiptCID,
                receiptData: receiptData,
                signature: signature,
                senderDID: senderDID,
                receivedAt: receivedAt,
                parentCID: parentCID
            )
        }
    }

    // MARK: - Helper

    /**
     * Get Firebase auth token for relay requests
     */
    private func getFirebaseToken() async throws -> String {
        // Use existing authHeader() method from RelayClient
        let headers = try await authHeader()
        return headers["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
    }
}
