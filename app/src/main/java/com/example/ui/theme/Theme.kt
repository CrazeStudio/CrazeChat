package com.example.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF60A5FA),
    onPrimary = Color.Black,
    primaryContainer = Color(0xFF1E3A8A),
    onPrimaryContainer = Color(0xFFDBEAFE),
    secondary = Color(0xFF38BDF8),
    background = CrazeDarkBackground,
    surface = CrazeDarkSurface,
    surfaceVariant = CrazeDarkSurfaceVariant,
    onBackground = CrazeDarkTextPrimary,
    onSurface = CrazeDarkTextPrimary,
    onSurfaceVariant = CrazeDarkTextSecondary,
    outline = Color(0xFF475569),
    outlineVariant = Color(0xFF334155),
    error = CrazeError
)

private val LightColorScheme = lightColorScheme(
    primary = CrazePrimary,
    onPrimary = CrazeOnPrimary,
    primaryContainer = CrazePrimaryContainer,
    onPrimaryContainer = CrazeOnPrimaryContainer,
    secondary = CrazePrimary,
    onSecondary = CrazeOnPrimary,
    secondaryContainer = CrazeSurface,
    onSecondaryContainer = CrazeTextPrimary,
    background = CrazeBackground,
    surface = CrazeBackground,
    surfaceVariant = CrazeSurface,
    onBackground = CrazeTextPrimary,
    onSurface = CrazeTextPrimary,
    onSurfaceVariant = CrazeTextSecondary,
    outline = CrazeOutline,
    outlineVariant = CrazeOutlineVariant,
    error = CrazeError
)

@Composable
fun CrazeChatTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val currentDensity = LocalDensity.current
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val screenWidthDp = configuration.screenWidthDp

    // Auto-scale font sizes dynamically based on screen width to make text highly readable.
    // Base width is around 360dp (standard phone). Larger devices/Tablets scale text up beautifully for readability,
    // while smaller screens scale down slightly to prevent clipping and ugly wrapping.
    val scaleFactor = (screenWidthDp / 360f).coerceIn(0.95f, 1.25f)
    val customDensity = Density(
        density = currentDensity.density,
        fontScale = currentDensity.fontScale * scaleFactor
    )

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography
    ) {
        CompositionLocalProvider(
            LocalDensity provides customDensity,
            content = content
        )
    }
}
