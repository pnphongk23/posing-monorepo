package com.aipose.purchases

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.SecondaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import com.aipose.platform.LegalDocument
import com.aipose.platform.openLegalDocument
import kotlinx.coroutines.launch
import androidx.compose.runtime.collectAsState

enum class PaidAccessTrigger { TRY_POSE, CAMERA_CAPTURE, GALLERY_SAVE_SHARE }

data class GateDecision(val showPaywall: Boolean, val allowAction: Boolean)

fun decidePaidAccess(snapshot: PurchaseSnapshot): GateDecision =
    GateDecision(showPaywall = !snapshot.hasConfirmedPremium, allowAction = snapshot.hasConfirmedPremium)

fun decidePaidAccess(trigger: PaidAccessTrigger, snapshot: PurchaseSnapshot): GateDecision =
    decidePaidAccess(snapshot)

/** One Compose surface for every approved paid-access trigger. */
@Composable
fun PaywallScreen(
    gateway: PurchaseGateway,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    onTerms: () -> Unit = { openLegalDocument(LegalDocument.TERMS) },
    onPrivacy: () -> Unit = { openLegalDocument(LegalDocument.PRIVACY) },
) {
    val snapshot by gateway.snapshot.collectAsState()
    var hasLoaded by remember { mutableStateOf(false) }
    var selectedProduct by remember { mutableStateOf("premium_annual") }
    val scope = rememberCoroutineScope()
    val offering = snapshot.offering
    val selected = offering?.products?.firstOrNull { it.identifier == selectedProduct }
    val busy = snapshot.state == PurchaseState.LOADING || snapshot.state == PurchaseState.PURCHASE_PENDING

    androidx.compose.runtime.LaunchedEffect(gateway) {
        gateway.loadOffering()
        hasLoaded = true
    }

    Box(
        modifier = modifier.fillMaxSize().background(AiPoseColors.Background).testTag("paywall"),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Premium access", style = AiPoseTypography.Heading2, color = AiPoseColors.Foreground)
                NeoBrutalismContainer(
                    modifier = Modifier.size(44.dp),
                    shape = RoundedCornerShape(10.dp),
                    backgroundColor = AiPoseColors.Background,
                    shadowOffset = 2.dp,
                    borderWidth = 2.dp,
                    onClick = onDismiss,
                ) { Icon(Icons.Default.Close, "Close", tint = AiPoseColors.Foreground) }
            }
            Text("Unlock Try Pose, Camera capture, and Gallery save/share.", style = AiPoseTypography.Heading3, color = AiPoseColors.Foreground)
            Text("No trial or introductory offer. Prices and periods come from the App Store locale.", style = AiPoseTypography.Body, color = AiPoseColors.Subtext)

            when {
                snapshot.state == PurchaseState.UNCONFIGURED -> {
                    Text("Premium is temporarily unavailable. Please try again later.", color = AiPoseColors.Error, modifier = Modifier.testTag("paywall-unconfigured"))
                    SecondaryButton(text = "Retry", onClick = { scope.launch { gateway.loadOffering() } }, modifier = Modifier.fillMaxWidth().testTag("paywall-retry"))
                }
                snapshot.state == PurchaseState.NO_OFFERING -> {
                    Text("Plans are temporarily unavailable. Retry to check again.", color = AiPoseColors.Error, modifier = Modifier.testTag("paywall-no-offering"))
                    SecondaryButton(text = "Retry", onClick = { scope.launch { gateway.loadOffering() } }, modifier = Modifier.fillMaxWidth().testTag("paywall-retry"))
                }
                busy -> CircularProgressIndicator(color = AiPoseColors.Primary, modifier = Modifier.testTag("paywall-loading"))
                offering == null && !hasLoaded -> Text("Loading plans…", color = AiPoseColors.Subtext)
                else -> offering?.products?.forEach { product ->
                    val isSelected = product.identifier == selectedProduct
                    val label = product.identifier.removePrefix("premium_").replace('_', ' ').replaceFirstChar { it.uppercase() }
                    NeoBrutalismContainer(
                        modifier = Modifier.fillMaxWidth().border(if (isSelected) 3.dp else 2.dp, if (isSelected) AiPoseColors.Foreground else AiPoseColors.Subtext, RoundedCornerShape(12.dp)).testTag("paywall-plan-${product.identifier}"),
                        shape = RoundedCornerShape(12.dp),
                        backgroundColor = if (product.isAnnualHighlight) AiPoseColors.Warning else AiPoseColors.Surface,
                        shadowOffset = if (isSelected) 3.dp else 2.dp,
                        borderWidth = 0.dp,
                        onClick = { selectedProduct = product.identifier },
                    ) {
                        Column(Modifier.fillMaxWidth().padding(Spacing.md)) {
                            Text(if (product.isAnnualHighlight) "$label • Recommended" else label, style = AiPoseTypography.BodyBold, color = AiPoseColors.Foreground)
                            Text(listOfNotNull(product.localizedPrice, product.period?.let { "/ $it" }).joinToString(" "), style = AiPoseTypography.Body, color = AiPoseColors.Foreground)
                        }
                    }
                }
            }

            PrimaryButton(
                text = when {
                    busy -> "Processing…"
                    selected == null -> "Plans unavailable"
                    else -> "Subscribe for ${selected.localizedPrice} / ${selected.period ?: "period"}"
                },
                onClick = {
                    selected?.let { product -> scope.launch { gateway.purchase(product.identifier) } }
                },
                modifier = Modifier.fillMaxWidth().testTag("paywall-primary-cta"),
            )
            if (snapshot.state == PurchaseState.PURCHASE_FAILED || snapshot.state == PurchaseState.PURCHASE_CANCELLED) {
                Text(if (snapshot.state == PurchaseState.PURCHASE_CANCELLED) "Purchase cancelled. No access was granted." else "Purchase could not be completed. Try again.", color = AiPoseColors.Error, modifier = Modifier.testTag("paywall-purchase-error"))
            }
            if (snapshot.hasConfirmedPremium) Text("Premium access confirmed.", color = AiPoseColors.Foreground, modifier = Modifier.testTag("paywall-success"))
            PrimaryButton(text = "Restore Purchases", onClick = { scope.launch { gateway.restore() } }, modifier = Modifier.fillMaxWidth().testTag("paywall-restore"))
            Text("Subscriptions renew until cancelled in App Store settings. No trial or introductory offer.", style = AiPoseTypography.Caption, color = AiPoseColors.Subtext)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                Text("Terms of Use", color = AiPoseColors.Foreground, modifier = Modifier
                    .clickable(onClick = onTerms)
                    .semantics { role = Role.Button }
                    .testTag("paywall-terms"))
                Spacer(Modifier.size(Spacing.md))
                Text("Privacy Policy", color = AiPoseColors.Foreground, modifier = Modifier
                    .clickable(onClick = onPrivacy)
                    .semantics { role = Role.Button }
                    .testTag("paywall-privacy"))
            }
            // Legal destinations are injected by the host; no URL is stored here.
        }
    }
}
