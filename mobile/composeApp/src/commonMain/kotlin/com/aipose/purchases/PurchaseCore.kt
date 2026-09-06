package com.aipose.purchases

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** The only entitlement used by FEAT-011. */
object PurchaseConfiguration {
    const val PREMIUM_ENTITLEMENT = "snap pose premium"
    const val DEFAULT_OFFERING = "default"
    val PRODUCT_IDS = listOf(
        "premium_monthly",
        "premium_yearly",
    )
}

enum class PurchaseCapability {
    TRY_POSE,
    CAMERA_CAPTURE,
    GALLERY_SAVE_SHARE,
}

enum class PurchaseState {
    UNKNOWN,
    LOADING,
    READY,
    NOT_ENTITLED,
    ENTITLED,
    PURCHASE_PENDING,
    PURCHASE_CANCELLED,
    PURCHASE_FAILED,
    EXPIRED,
    BILLING_RETRY,
    GRACE_PERIOD,
    REVOKED,
    NO_OFFERING,
    UNCONFIGURED,
}

data class LocalizedProduct(
    val identifier: String,
    val localizedPrice: String,
    val period: String?,
    val isAnnualHighlight: Boolean = false,
)

data class PurchaseOffering(
    val identifier: String,
    val products: List<LocalizedProduct>,
)

data class PurchaseSnapshot(
    val state: PurchaseState = PurchaseState.UNKNOWN,
    val offering: PurchaseOffering? = null,
    val errorCode: String? = null,
) {
    val hasConfirmedPremium: Boolean get() = state == PurchaseState.ENTITLED

    fun canUse(capability: PurchaseCapability): Boolean = hasConfirmedPremium && capability in setOf(
        PurchaseCapability.TRY_POSE,
        PurchaseCapability.CAMERA_CAPTURE,
        PurchaseCapability.GALLERY_SAVE_SHARE,
    )
}

/**
 * Common contract implemented by the native RevenueCat adapter and by tests.
 * Implementations must publish confirmed CustomerInfo entitlement state; a
 * local boolean must never be used as an authority for access.
 */
interface PurchaseGateway {
    val snapshot: StateFlow<PurchaseSnapshot>
    suspend fun loadOffering(): PurchaseSnapshot
    suspend fun purchase(productId: String): PurchaseSnapshot
    suspend fun restore(): PurchaseSnapshot
}

/** Production-safe default until the native host injects its RevenueCat bridge. */
object UnconfiguredPurchaseGateway : PurchaseGateway {
    override val snapshot = MutableStateFlow(PurchaseSnapshot(state = PurchaseState.UNCONFIGURED))
    override suspend fun loadOffering() = snapshot.value
    override suspend fun purchase(productId: String) = snapshot.value
    override suspend fun restore() = snapshot.value
}

/** Deterministic fixture for common tests and local UI matrix verification. */
class FakePurchaseGateway(
    private val offering: PurchaseOffering? = PurchaseFixtures.defaultOffering,
) : PurchaseGateway {
    override val snapshot = MutableStateFlow(PurchaseSnapshot(state = PurchaseState.UNKNOWN))

    var nextPurchaseState: PurchaseState = PurchaseState.ENTITLED
    var nextRestoreState: PurchaseState = PurchaseState.NOT_ENTITLED
    var loadCount: Int = 0
        private set
    var restoreCount: Int = 0
        private set
    val purchasedProductIds = mutableListOf<String>()

    override suspend fun loadOffering(): PurchaseSnapshot {
        loadCount += 1
        return transition(if (offering == null) PurchaseState.NO_OFFERING else PurchaseState.READY)
    }

    override suspend fun purchase(productId: String): PurchaseSnapshot {
        purchasedProductIds += productId
        return transition(if (productId in PurchaseConfiguration.PRODUCT_IDS) nextPurchaseState else PurchaseState.PURCHASE_FAILED)
    }

    override suspend fun restore(): PurchaseSnapshot {
        restoreCount += 1
        return transition(nextRestoreState)
    }

    private fun transition(next: PurchaseState): PurchaseSnapshot {
        val nextSnapshot = PurchaseSnapshot(
            state = next,
            offering = if (next == PurchaseState.READY) offering else snapshot.value.offering,
        )
        snapshot.value = nextSnapshot
        return nextSnapshot
    }
}

object PurchaseBridgeNotifications {
    const val REQUEST = "com.aipose.revenuecat.request"
    const val RESPONSE = "com.aipose.revenuecat.response"
}

expect fun platformPurchaseGateway(): PurchaseGateway

object PurchaseGatewayProvider {
    val current: PurchaseGateway get() = platformPurchaseGateway()
}

object PurchaseFixtures {
    /** Prices are deliberately fixture labels; StoreKit metadata is authoritative in production. */
    val defaultOffering = PurchaseOffering(
        identifier = PurchaseConfiguration.DEFAULT_OFFERING,
        products = listOf(
            LocalizedProduct("premium_monthly", "localized", "month"),
            LocalizedProduct("premium_yearly", "localized", "year", isAnnualHighlight = true),
        ),
    )
}
