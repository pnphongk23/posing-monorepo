package com.aipose.purchases

import kotlinx.cinterop.BetaInteropApi
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import platform.Foundation.NSArray
import platform.Foundation.NSDictionary
import platform.Foundation.NSNotification
import platform.Foundation.NSNotificationCenter
import platform.Foundation.NSOperationQueue
import platform.Foundation.NSUUID
import kotlin.coroutines.resume

/**
 * Thin notification bridge: Swift owns RevenueCat/StoreKit, while this KMP
 * gateway owns the observable Compose state and request lifecycle.
 */
@OptIn(BetaInteropApi::class)
object IosRevenueCatGateway : PurchaseGateway {
    override val snapshot = MutableStateFlow(PurchaseSnapshot(state = PurchaseState.UNCONFIGURED))
    private val pending = mutableMapOf<String, (PurchaseSnapshot) -> Unit>()
    private val observer = NSNotificationCenter.defaultCenter.addObserverForName(
        name = PurchaseBridgeNotifications.RESPONSE,
        `object` = null,
        queue = NSOperationQueue.mainQueue,
    ) { notification -> receive(notification) }

    private fun receive(notification: NSNotification?) {
        val info = notification?.userInfo ?: return
        val mapped = snapshotFrom(info) ?: return
        snapshot.value = mapped
        val requestId = info["requestId"] as? String ?: return
        pending.remove(requestId)?.invoke(mapped)
    }

    private fun snapshotFrom(info: Map<Any?, *>): PurchaseSnapshot? {
        val state = (info["state"] as? String)?.let { value ->
            PurchaseState.entries.firstOrNull { it.name == value }
        } ?: return null
        return PurchaseSnapshot(
            state = state,
            offering = offeringFrom(info["products"] as? NSArray) ?: snapshot.value.offering,
            errorCode = info["errorCode"] as? String,
        )
    }

    private fun offeringFrom(raw: NSArray?): PurchaseOffering? {
        val products = raw?.let { array -> (0 until array.count.toInt()).mapNotNull { index ->
            val value = array.objectAtIndex(index.toULong()) as? NSDictionary ?: return@mapNotNull null
            val id = value.objectForKey("identifier") as? String ?: return@mapNotNull null
            if (id !in PurchaseConfiguration.PRODUCT_IDS) return@mapNotNull null
            LocalizedProduct(id, value.objectForKey("localizedPrice") as? String ?: return@mapNotNull null, value.objectForKey("period") as? String, id == "premium_annual")
        } }?.takeIf { it.isNotEmpty() } ?: return null
        return PurchaseOffering(PurchaseConfiguration.DEFAULT_OFFERING, products)
    }

    override suspend fun loadOffering(): PurchaseSnapshot = request("load_offering")
    override suspend fun purchase(productId: String): PurchaseSnapshot = request("purchase", productId)
    override suspend fun restore(): PurchaseSnapshot = request("restore")

    private suspend fun request(action: String, productId: String? = null): PurchaseSnapshot =
        suspendCancellableCoroutine { continuation ->
            val requestId = NSUUID().UUIDString
            pending[requestId] = { result -> if (continuation.isActive) continuation.resume(result) }
            val values = mutableMapOf<Any?, Any?>("requestId" to requestId, "action" to action)
            productId?.let { values["productId"] = it }
            NSNotificationCenter.defaultCenter.postNotificationName(
                aName = PurchaseBridgeNotifications.REQUEST,
                `object` = null,
                userInfo = values,
            )
            continuation.invokeOnCancellation { pending.remove(requestId) }
        }
}

actual fun platformPurchaseGateway(): PurchaseGateway = IosRevenueCatGateway
