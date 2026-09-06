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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.aipose.platform.ExternalActionResult
import com.aipose.platform.LegalDocument
import com.aipose.platform.openLegalDocument
import com.aipose.ui.components.NeoBrutalismContainer
import com.aipose.ui.components.PrimaryButton
import com.aipose.ui.components.SecondaryButton
import com.aipose.ui.theme.AiPoseColors
import com.aipose.ui.theme.AiPoseTypography
import com.aipose.ui.theme.Spacing
import kotlinx.coroutines.launch

enum class PaidAccessTrigger { TRY_POSE, CAMERA_CAPTURE, GALLERY_SAVE_SHARE }

data class GateDecision(val showPaywall: Boolean, val allowAction: Boolean)

fun decidePaidAccess(snapshot: PurchaseSnapshot): GateDecision =
    GateDecision(showPaywall = !snapshot.hasConfirmedPremium, allowAction = snapshot.hasConfirmedPremium)

fun decidePaidAccess(trigger: PaidAccessTrigger, snapshot: PurchaseSnapshot): GateDecision =
    decidePaidAccess(snapshot)

internal fun paywallLegalActionMessage(result: ExternalActionResult): String? = when (result) {
    ExternalActionResult.Opened -> null
    ExternalActionResult.NotConfigured -> "Terms and privacy links are not available on this device."
    is ExternalActionResult.Failed -> if (result.retryable) {
        "Could not open the link. Please try again."
    } else {
        "The legal link is invalid."
    }
}

/** One Compose surface for every approved paid-access trigger. */
@Composable
fun PaywallScreen(
    gateway: PurchaseGateway,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    onTerms: suspend () -> ExternalActionResult = { openLegalDocument(LegalDocument.TERMS) },
    onPrivacy: suspend () -> ExternalActionResult = { openLegalDocument(LegalDocument.PRIVACY) },
) {
    val snapshot by gateway.snapshot.collectAsState()
    var hasLoaded by remember { mutableStateOf(false) }
    var selectedProduct by remember { mutableStateOf("premium_yearly") }
    var legalDialogMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun launchLegalAction(action: suspend () -> ExternalActionResult) {
        scope.launch {
            paywallLegalActionMessage(action())?.let { legalDialogMessage = it }
        }
    }
    val offering = snapshot.offering
    val selected = offering?.products?.firstOrNull { it.identifier == selectedProduct }
        ?: offering?.products?.firstOrNull { it.isAnnualHighlight }
        ?: offering?.products?.firstOrNull()
    val busy = snapshot.state == PurchaseState.LOADING || snapshot.state == PurchaseState.PURCHASE_PENDING

    LaunchedEffect(gateway) {
        gateway.loadOffering()
        hasLoaded = true
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(AiPoseColors.Background)
            .testTag("paywall")
            .testTag("paywall-screen"),
    ) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .border(width = 1.dp, color = AiPoseColors.Border, shape = RoundedCornerShape(0.dp))
                    .padding(horizontal = Spacing.lg, vertical = Spacing.sm),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(11.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(width = 5.dp, height = 34.dp)
                            .background(AiPoseColors.Warning, RoundedCornerShape(99.dp))
                            .border(1.dp, AiPoseColors.Foreground, RoundedCornerShape(99.dp)),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = "AI POSE",
                            style = AiPoseTypography.Caption.copy(
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.16.em,
                            ),
                            color = AiPoseColors.Subtext,
                        )
                        Text(
                            text = "Premium studio",
                            style = AiPoseTypography.NavigationTitle.copy(
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = (-0.02).em,
                            ),
                            color = AiPoseColors.Foreground,
                        )
                    }
                }
                NeoBrutalismContainer(
                    modifier = Modifier
                        .size(44.dp)
                        .testTag("paywall-close-button")
                        .testTag("paywall-close"),
                    shape = RoundedCornerShape(999.dp),
                    backgroundColor = AiPoseColors.Foreground,
                    borderColor = AiPoseColors.Foreground,
                    borderWidth = 1.5.dp,
                    shadowOffset = 2.dp,
                    hasShadow = false,
                    onClick = onDismiss,
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close Premium and go back",
                        tint = AiPoseColors.Background,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }

            // Scrollable main content
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Spacing.lg, vertical = Spacing.md),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                // Story Section
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Text(
                        text = "Pose with confidence.",
                        style = AiPoseTypography.Display.copy(
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = (-0.03).em,
                            lineHeight = 32.sp,
                        ),
                        color = AiPoseColors.Foreground,
                    )
                    Text(
                        text = "Explore poses, frame the shot, and keep every favorite.",
                        style = AiPoseTypography.Body.copy(
                            fontSize = 16.sp,
                            lineHeight = 23.sp,
                        ),
                        color = AiPoseColors.Foreground,
                    )

                    // 3-Benefit Dark Panel
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp)
                            .background(AiPoseColors.Foreground, RoundedCornerShape(16.dp))
                            .border(2.dp, AiPoseColors.Foreground, RoundedCornerShape(16.dp))
                            .padding(vertical = 14.dp, horizontal = 8.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        BenefitItem(
                            modifier = Modifier.weight(1f),
                            icon = Icons.Default.Search,
                            title = "Discover",
                            subtitle = "Community poses",
                        )
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(36.dp)
                                .background(Color(0xFFFAF6EF).copy(alpha = 0.22f)),
                        )
                        BenefitItem(
                            modifier = Modifier.weight(1f),
                            icon = Icons.Default.CameraAlt,
                            title = "Frame",
                            subtitle = "Full pose camera",
                        )
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(36.dp)
                                .background(Color(0xFFFAF6EF).copy(alpha = 0.22f)),
                        )
                        BenefitItem(
                            modifier = Modifier.weight(1f),
                            icon = Icons.Default.Share,
                            title = "Keep",
                            subtitle = "Save and share",
                        )
                    }
                }

                // Offer Section
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Text(
                        text = "Choose your plan",
                        style = AiPoseTypography.Heading3.copy(
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = (-0.02).em,
                        ),
                        color = AiPoseColors.Foreground,
                    )

                    when {
                        snapshot.state == PurchaseState.UNCONFIGURED -> {
                            Text(
                                text = "Premium is temporarily unavailable. Please try again later.",
                                color = AiPoseColors.Error,
                                style = AiPoseTypography.Body,
                                modifier = Modifier.testTag("paywall-unconfigured").testTag("paywall-message"),
                            )
                            SecondaryButton(
                                text = "Retry",
                                onClick = { scope.launch { gateway.loadOffering() } },
                                modifier = Modifier.fillMaxWidth().testTag("paywall-retry"),
                            )
                        }
                        snapshot.state == PurchaseState.NO_OFFERING -> {
                            Text(
                                text = "Plans are temporarily unavailable. Retry to check again.",
                                color = AiPoseColors.Error,
                                style = AiPoseTypography.Body,
                                modifier = Modifier.testTag("paywall-no-offering").testTag("paywall-message"),
                            )
                            SecondaryButton(
                                text = "Retry",
                                onClick = { scope.launch { gateway.loadOffering() } },
                                modifier = Modifier.fillMaxWidth().testTag("paywall-retry"),
                            )
                        }
                        busy -> {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(
                                    color = AiPoseColors.Primary,
                                    modifier = Modifier.testTag("paywall-loading").testTag("paywall-indicator-loading"),
                                )
                            }
                        }
                        offering == null && !hasLoaded -> {
                            Text("Loading plans…", color = AiPoseColors.Subtext, style = AiPoseTypography.Body)
                        }
                        else -> {
                            val products = offering?.products.orEmpty()
                            val orderedProducts = products.sortedByDescending {
                                it.isAnnualHighlight || it.identifier.contains("year") || it.identifier.contains("annual")
                            }
                            orderedProducts.forEach { product ->
                                val isSelected = product.identifier == (selected?.identifier ?: selectedProduct)
                                val isAnnual = product.isAnnualHighlight || product.identifier.contains("year") || product.identifier.contains("annual")
                                val planLabel = if (isAnnual) {
                                    "Annual"
                                } else if (product.identifier.contains("month")) {
                                    "Monthly"
                                } else {
                                    product.identifier.removePrefix("premium_").replace('_', ' ').replaceFirstChar { it.uppercase() }
                                }
                                val periodLabel = product.period ?: if (isAnnual) "year" else "month"
                                val termsText = if (isAnnual) {
                                    "Billed today. Auto-renews yearly until you cancel."
                                } else {
                                    "Billed today. Auto-renews monthly until you cancel."
                                }

                                PlanOptionCard(
                                    product = product,
                                    planLabel = planLabel,
                                    periodLabel = periodLabel,
                                    termsText = termsText,
                                    isRecommended = isAnnual,
                                    isSelected = isSelected,
                                    onClick = { selectedProduct = product.identifier },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("paywall-plan-${product.identifier}")
                                        .testTag(if (isAnnual) "paywall-action-annual" else "paywall-action-monthly"),
                                )
                            }
                        }
                    }
                }

                if (snapshot.state == PurchaseState.PURCHASE_FAILED || snapshot.state == PurchaseState.PURCHASE_CANCELLED) {
                    Text(
                        text = if (snapshot.state == PurchaseState.PURCHASE_CANCELLED) {
                            "Purchase cancelled. No access was granted."
                        } else {
                            "Purchase could not be completed. Try again."
                        },
                        color = AiPoseColors.Error,
                        style = AiPoseTypography.Body.copy(fontWeight = FontWeight.Medium),
                        modifier = Modifier.testTag("paywall-purchase-error").testTag("paywall-message"),
                    )
                }

                if (snapshot.hasConfirmedPremium) {
                    Text(
                        text = "Premium access confirmed.",
                        color = AiPoseColors.SuccessForeground,
                        style = AiPoseTypography.Body.copy(fontWeight = FontWeight.Bold),
                        modifier = Modifier.testTag("paywall-success"),
                    )
                }
            }

            // Bottom Sticky Dock
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AiPoseColors.Background)
                    .border(
                        width = 1.dp,
                        color = AiPoseColors.Border,
                        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
                    )
                    .padding(horizontal = Spacing.lg, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                val selectedIsAnnual = selected?.let {
                    it.isAnnualHighlight || it.identifier.contains("year") || it.identifier.contains("annual")
                } ?: true
                val ctaText = when {
                    busy -> "Processing…"
                    selected == null -> "Plans unavailable"
                    selectedIsAnnual -> "Continue with Annual"
                    else -> "Continue with ${selected.identifier.removePrefix("premium_").replace('_', ' ').replaceFirstChar { it.uppercase() }}"
                }

                PrimaryButton(
                    text = ctaText,
                    onClick = {
                        selected?.let { product -> scope.launch { gateway.purchase(product.identifier) } }
                    },
                    enabled = !busy && selected != null,
                    modifier = Modifier.fillMaxWidth().testTag("paywall-primary-cta"),
                )

                if (selected != null) {
                    val periodCadence = if (selectedIsAnnual) "yearly" else "monthly"
                    Text(
                        text = "${selected.localizedPrice} billed today. Auto-renews $periodCadence until you cancel.",
                        style = AiPoseTypography.Caption.copy(fontSize = 12.sp),
                        color = AiPoseColors.Subtext,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Restore purchases",
                        style = AiPoseTypography.Caption.copy(
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = AiPoseColors.Foreground,
                        textDecoration = TextDecoration.Underline,
                        modifier = Modifier
                            .clickable { scope.launch { gateway.restore() } }
                            .semantics { role = Role.Button }
                            .testTag("paywall-restore")
                            .testTag("paywall-action-restore")
                            .padding(horizontal = 6.dp, vertical = 4.dp),
                    )
                    Text("•", color = AiPoseColors.Subtext, modifier = Modifier.padding(horizontal = 2.dp))
                    Text(
                        text = "Terms",
                        style = AiPoseTypography.Caption.copy(
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = AiPoseColors.Foreground,
                        textDecoration = TextDecoration.Underline,
                        modifier = Modifier
                            .padding(horizontal = 6.dp, vertical = 4.dp)
                            .clickable { launchLegalAction(onTerms) }
                            .semantics { role = Role.Button }
                            .testTag("paywall-terms"),
                    )
                    Text("•", color = AiPoseColors.Subtext, modifier = Modifier.padding(horizontal = 2.dp))
                    Text(
                        text = "Privacy",
                        style = AiPoseTypography.Caption.copy(
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = AiPoseColors.Foreground,
                        textDecoration = TextDecoration.Underline,
                        modifier = Modifier
                            .padding(horizontal = 6.dp, vertical = 4.dp)
                            .clickable { launchLegalAction(onPrivacy) }
                            .semantics { role = Role.Button }
                            .testTag("paywall-privacy"),
                    )
                }

                Text(
                    text = "Cancel anytime in App Store settings. No free trial.",
                    style = AiPoseTypography.Caption.copy(fontSize = 11.sp),
                    color = AiPoseColors.Subtext,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }

    legalDialogMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { legalDialogMessage = null },
            title = {
                Text(
                    text = "Unable to open link",
                    style = AiPoseTypography.Heading3,
                    color = AiPoseColors.Foreground,
                )
            },
            text = {
                Text(
                    text = message,
                    style = AiPoseTypography.Body,
                    color = AiPoseColors.Subtext,
                )
            },
            confirmButton = {
                TextButton(onClick = { legalDialogMessage = null }) {
                    Text("OK", color = AiPoseColors.Foreground)
                }
            },
            modifier = Modifier.testTag("paywall-legal-error-dialog"),
        )
    }
}

@Composable
private fun BenefitItem(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    title: String,
    subtitle: String,
) {
    Column(
        modifier = modifier.padding(horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = AiPoseColors.Warning,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = title,
            style = AiPoseTypography.Body.copy(
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            ),
            color = Color(0xFFFAF6EF),
        )
        Text(
            text = subtitle,
            style = AiPoseTypography.Caption.copy(
                fontSize = 11.sp,
                fontWeight = FontWeight.Normal,
            ),
            color = Color(0xFFFAF6EF).copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun PlanOptionCard(
    product: LocalizedProduct,
    planLabel: String,
    periodLabel: String,
    termsText: String,
    isRecommended: Boolean,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    NeoBrutalismContainer(
        modifier = modifier,
        shape = shape,
        backgroundColor = AiPoseColors.Surface,
        borderColor = if (isSelected) AiPoseColors.Foreground else AiPoseColors.Border,
        borderWidth = if (isSelected) 3.dp else 1.5.dp,
        shadowOffset = if (isSelected) 3.dp else 1.dp,
        hasShadow = isSelected,
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(20.dp)
                        .background(AiPoseColors.Surface, RoundedCornerShape(999.dp))
                        .border(
                            width = 1.5.dp,
                            color = if (isSelected) AiPoseColors.Foreground else AiPoseColors.Subtext,
                            shape = RoundedCornerShape(999.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isSelected) {
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .background(AiPoseColors.Foreground, RoundedCornerShape(999.dp)),
                        )
                    }
                }
                Text(
                    text = planLabel.uppercase(),
                    style = AiPoseTypography.Control.copy(
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 0.08.em,
                    ),
                    color = AiPoseColors.Foreground,
                )
                if (isRecommended) {
                    Spacer(Modifier.weight(1f))
                    Box(
                        modifier = Modifier
                            .background(AiPoseColors.Warning, RoundedCornerShape(4.dp))
                            .border(1.dp, AiPoseColors.Foreground, RoundedCornerShape(4.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = "RECOMMENDED",
                            style = AiPoseTypography.Caption.copy(
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.04.em,
                            ),
                            color = AiPoseColors.Foreground,
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = product.localizedPrice,
                    style = AiPoseTypography.Display.copy(
                        fontSize = if (isRecommended) 28.sp else 22.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.03).em,
                    ),
                    color = AiPoseColors.Foreground,
                )
                Text(
                    text = "/ $periodLabel",
                    style = AiPoseTypography.Body.copy(
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    color = AiPoseColors.Foreground,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }

            Text(
                text = termsText,
                style = AiPoseTypography.Caption.copy(
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                ),
                color = AiPoseColors.Subtext,
            )
        }
    }
}
