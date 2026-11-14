package com.crazestudio.crazechat

import android.content.Intent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.crazestudio.crazechat.data.ChatSummary
import com.crazestudio.crazechat.data.ChatUser
import com.crazestudio.crazechat.security.CryptoService
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val Ink: Color @Composable get() = MaterialTheme.colorScheme.background
private val Panel: Color @Composable get() = MaterialTheme.colorScheme.surface
private val PanelRaised: Color @Composable get() = MaterialTheme.colorScheme.surfaceVariant
private val Purple: Color @Composable get() = MaterialTheme.colorScheme.primary
private val PurpleLight: Color @Composable get() = MaterialTheme.colorScheme.secondary
private val Muted: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
private val Green: Color @Composable get() = MaterialTheme.colorScheme.tertiary
private val Line: Color @Composable get() = MaterialTheme.colorScheme.outline
private val TextMain: Color @Composable get() = MaterialTheme.colorScheme.onSurface

@Composable
fun CrazeChatRoot(model: MainViewModel = viewModel()) {
    val state by model.state.collectAsState()
    val context = LocalContext.current
    val activity = context as? MainActivity
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.ready) {
        if (state.ready) activity?.consumeLaunchChatId()?.let(model::openChatById)
    }
    LaunchedEffect(state.screenSecureEnabled) {
        activity?.setScreenSecure(state.screenSecureEnabled)
    }
    LaunchedEffect(state.userId, state.notificationsEnabled) {
        if (state.userId != null && state.notificationsEnabled) activity?.requestNotificationPermission()
    }
    LaunchedEffect(state.error) {
        state.error?.let { snackbar.showSnackbar(it); model.consumeMessage() }
    }
    LaunchedEffect(state.info) {
        state.info?.let { snackbar.showSnackbar(it); model.consumeMessage() }
    }

    val effectiveTheme = if (state.themeMode == "system") {
        if (isSystemInDarkTheme()) "dark" else "light"
    } else state.themeMode
    val scheme = when (effectiveTheme) {
        "light" -> lightColorScheme(
            primary = Color(0xFF2766E8), onPrimary = Color.White,
            primaryContainer = Color(0xFFDCE8FF), onPrimaryContainer = Color(0xFF112E67),
            secondary = Color(0xFF548CFF), onSecondary = Color.White,
            secondaryContainer = Color(0xFFE8F0FF), onSecondaryContainer = Color(0xFF193B78),
            background = Color(0xFFF4F7FC), surface = Color(0xFFFFFFFF),
            surfaceVariant = Color(0xFFEBF0F8), onSurface = Color(0xFF142036),
            onSurfaceVariant = Color(0xFF64748B), outline = Color(0xFFD9E2EF),
            outlineVariant = Color(0xFFE7EDF5), tertiary = Color(0xFF159B84),
            error = Color(0xFFCF3E57)
        )
        else -> darkColorScheme(
            primary = Color(0xFF397BFF), onPrimary = Color.White,
            primaryContainer = Color(0xFF173C85), onPrimaryContainer = Color(0xFFE2ECFF),
            secondary = Color(0xFF69A0FF), onSecondary = Color(0xFF081D42),
            secondaryContainer = Color(0xFF203B68), onSecondaryContainer = Color(0xFFE4EEFF),
            background = Color(0xFF080F1D), surface = Color(0xFF111B2C),
            surfaceVariant = Color(0xFF1A2940), onSurface = Color(0xFFF4F7FF),
            onSurfaceVariant = Color(0xFF9EADC4), outline = Color(0xFF2B3D58),
            outlineVariant = Color(0xFF203149), tertiary = Color(0xFF4BD6B4),
            error = Color(0xFFFF718A)
        )
    }

    MaterialTheme(colorScheme = scheme) {
        Box(Modifier.fillMaxSize().background(Ink)) {
            if (!state.ready) {
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    BrandMark(66)
                    Spacer(Modifier.height(20.dp))
                    CircularProgressIndicator(color = PurpleLight, strokeWidth = 2.dp)
                }
            } else when (state.page) {
                AppPage.AUTH -> if (state.userId != null) UnlockPage(model, state) else AuthPage(model, state)
                AppPage.INBOX -> InboxPage(model, state)
                AppPage.CHAT -> ChatPage(model, state)
                AppPage.PROFILE -> ProfilePage(model, state)
                AppPage.SETTINGS -> SettingsPage(model, state)
                AppPage.PRIVACY -> PrivacyPage(model, state)
                AppPage.STORAGE -> StoragePage(model, state)
            }

            state.bannerChatId?.let {
                Row(
                    Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(12.dp)
                        .clip(RoundedCornerShape(18.dp)).background(PanelRaised)
                        .clickable { model.openBannerChat() }.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(Purple.copy(alpha = .2f)), contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.ChatBubble, null, tint = PurpleLight)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(state.bannerName ?: "New message", color = TextMain, fontWeight = FontWeight.Bold)
                        Text(
                            if (state.bannerCount > 1) "${state.bannerCount} new encrypted messages" else "New encrypted message",
                            color = Muted, fontSize = 11.sp
                        )
                    }
                    IconButton(onClick = model::dismissBanner) { Icon(Icons.Default.Close, "Dismiss", tint = Muted) }
                }
            }

            SnackbarHost(
                hostState = snackbar,
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp),
                snackbar = { data ->
                    Snackbar(
                        snackbarData = data,
                        containerColor = PanelRaised,
                        contentColor = TextMain,
                        shape = RoundedCornerShape(16.dp)
                    )
                }
            )
            if (state.loading) {
                Box(Modifier.fillMaxSize().background(Ink.copy(alpha = .35f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = PurpleLight)
                }
            }
        }
    }
}

@Composable
private fun BrandMark(size: Int) {
    Box(
        Modifier.size(size.dp).clip(RoundedCornerShape((size * .31f).dp))
            .background(Brush.linearGradient(listOf(Color(0xFF2367F4), Color(0xFF59A3FF))))
            .border(1.dp, Color.White.copy(alpha = .16f), RoundedCornerShape((size * .31f).dp)),
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Default.ChatBubble, contentDescription = "CrazeChat", tint = Color.White,
            modifier = Modifier.size((size * .48f).dp))
    }
}

@Composable
private fun BrandTitle(size: Int = 24) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        BrandMark(38)
        Spacer(Modifier.width(11.dp))
        Column {
            Text("CrazeChat", color = TextMain, fontSize = size.sp, fontWeight = FontWeight.ExtraBold)
            Text("PRIVATE. ENCRYPTED. YOURS.", color = Muted, fontSize = 9.sp,
                letterSpacing = 1.2.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun AuthPage(model: MainViewModel, state: CrazeUiState) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    val signup = state.signup
    val cleanUsername = username.trim()
    val usernameValid = Regex("^[a-zA-Z0-9_]{3,20}$").matches(cleanUsername)
    val passwordValid = password.length >= 12
    val formValid = usernameValid && passwordValid && (!signup || confirmation == password)
    Column(
        Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Ink, Panel.copy(alpha = .72f))))
            .imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(Modifier.height(12.dp))
        BrandTitle(26)
        Spacer(Modifier.height(30.dp))
        Text(if (signup) "Create your account" else "Welcome back",
            color = TextMain, fontSize = 29.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(6.dp))
        Text(if (signup) "A quieter, safer place for your conversations."
            else "Sign in to pick up where you left off.", color = Muted, fontSize = 14.sp)
        Spacer(Modifier.height(23.dp))
        Surface(color = Panel, shape = RoundedCornerShape(26.dp), tonalElevation = 2.dp,
            border = androidx.compose.foundation.BorderStroke(1.dp, Line.copy(alpha = .8f))) {
            Column(Modifier.fillMaxWidth().padding(18.dp)) {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(15.dp)).background(PanelRaised).padding(4.dp)) {
                    AuthTab("Log in", !signup, Modifier.weight(1f)) { model.setSignup(false) }
                    AuthTab("Sign up", signup, Modifier.weight(1f)) { model.setSignup(true) }
                }
                Spacer(Modifier.height(21.dp))
                FormLabel("USERNAME")
                DarkField(username, { username = it }, "Your username", leading = "@")
                Spacer(Modifier.height(15.dp))
                FormLabel("ACCOUNT PASSWORD")
                DarkField(password, { password = it }, "At least 12 characters", password = true)
                if (signup) {
                    Spacer(Modifier.height(15.dp))
                    FormLabel("CONFIRM PASSWORD")
                    DarkField(confirmation, { confirmation = it }, "Enter the password again", password = true)
                    Spacer(Modifier.height(14.dp))
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF16345D).copy(alpha = .55f)).padding(13.dp),
                        verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.Shield, null, tint = Color(0xFF70A8FF), modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text("Your private identity key is generated and protected automatically. There is no phrase to copy, write down or manage.",
                            color = TextMain, fontSize = 11.sp, lineHeight = 16.sp)
                    }
                    if (confirmation.isNotEmpty() && confirmation != password) {
                        Spacer(Modifier.height(7.dp))
                        Text("Passwords do not match.", color = MaterialTheme.colorScheme.error, fontSize = 11.sp)
                    }
                }
                Spacer(Modifier.height(20.dp))
                GradientButton(if (signup) "Create account" else "Log in",
                    enabled = formValid && !state.loading) {
                    model.authenticate(cleanUsername, password, signup)
                }
                Spacer(Modifier.height(13.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Lock, null, tint = Green, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("End-to-end encrypted direct messages", color = Muted, fontSize = 10.sp)
                }
            }
        }
        Spacer(Modifier.height(17.dp))
        Text("Usernames are public. Passwords and message contents are not shown to other people.",
            color = Muted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(horizontal = 4.dp))
    }
}

@Composable
private fun AuthTab(label: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.clip(RoundedCornerShape(15.dp))
            .background(if (selected) PanelRaised else Color.Transparent)
            .clickable(onClick = onClick).padding(vertical = 14.dp),
        contentAlignment = Alignment.Center
    ) { Text(label, color = if (selected) TextMain else Muted, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun FormLabel(value: String) {
    Text(value, color = TextMain, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(7.dp))
}

@Composable
private fun DarkField(
    value: String,
    onValueChange: (String) -> Unit,
    hint: String,
    password: Boolean = false,
    leading: String? = null,
    singleLine: Boolean = true
) {
    OutlinedTextField(
        value = value, onValueChange = onValueChange, modifier = Modifier.fillMaxWidth(),
        singleLine = singleLine,
        placeholder = { Text(hint, color = Muted.copy(alpha = .78f), fontSize = 14.sp) },
        leadingIcon = if (leading != null) ({ Text(leading, color = Muted, fontSize = 18.sp, fontWeight = FontWeight.Medium) }) else null,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = if (password) KeyboardOptions(keyboardType = KeyboardType.Password) else KeyboardOptions.Default,
        shape = RoundedCornerShape(17.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = PanelRaised, unfocusedContainerColor = PanelRaised,
            disabledContainerColor = PanelRaised.copy(alpha = .65f),
            focusedBorderColor = Purple, unfocusedBorderColor = Line,
            focusedTextColor = TextMain, unfocusedTextColor = TextMain, disabledTextColor = Muted,
            cursorColor = Purple, focusedPlaceholderColor = Muted, unfocusedPlaceholderColor = Muted
        )
    )
}

@Composable
private fun GradientButton(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().height(54.dp),
        shape = RoundedCornerShape(17.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Purple, contentColor = Color.White,
            disabledContainerColor = PanelRaised, disabledContentColor = Muted
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 1.dp)
    ) { Text(label, fontWeight = FontWeight.Bold, fontSize = 15.sp) }
}

@Composable
private fun UnlockPage(model: MainViewModel, state: CrazeUiState) {
    var password by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize()
        .background(Brush.verticalGradient(listOf(Ink, Panel.copy(alpha = .72f))))
        .imePadding().padding(horizontal = 25.dp), verticalArrangement = Arrangement.Center) {
        BrandMark(62)
        Spacer(Modifier.height(25.dp))
        Text("Welcome back", color = TextMain, fontSize = 29.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(5.dp))
        Text("@${state.username}", color = PurpleLight, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(11.dp))
        Text("Enter your CrazeChat account password to unlock your conversations.",
            color = Muted, fontSize = 13.sp, lineHeight = 19.sp)
        Spacer(Modifier.height(24.dp))
        FormLabel("ACCOUNT PASSWORD")
        DarkField(password, { password = it }, "Your account password", password = true)
        Spacer(Modifier.height(17.dp))
        GradientButton("Unlock CrazeChat", enabled = password.length >= 12 && !state.loading) { model.unlock(password) }
        TextButton(onClick = { model.signOut() }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text("Sign in to another account", color = Muted)
        }
    }
}

@Composable
private fun InboxPage(model: MainViewModel, state: CrazeUiState) {
    var showNewChat by remember { mutableStateOf(false) }
    Scaffold(
        containerColor = Ink,
        floatingActionButton = {
            FloatingActionButton(onClick = { showNewChat = true }, containerColor = Purple,
                contentColor = Color.White, shape = RoundedCornerShape(19.dp)) {
                Icon(Icons.Default.Edit, contentDescription = "New conversation")
            }
        },
        bottomBar = { BottomTabs(AppPage.INBOX, model) }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(Modifier.fillMaxWidth().padding(start = 21.dp, end = 16.dp, top = 15.dp, bottom = 17.dp),
                verticalAlignment = Alignment.CenterVertically) {
                BrandMark(42)
                Spacer(Modifier.width(11.dp))
                Column(Modifier.weight(1f)) {
                    Text("CrazeChat", color = TextMain, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Private conversations", color = Muted, fontSize = 11.sp)
                }
                if (state.refreshingChats) {
                    CircularProgressIndicator(Modifier.size(19.dp), color = PurpleLight, strokeWidth = 2.dp)
                    Spacer(Modifier.width(7.dp))
                }
                IconButton(onClick = { model.refreshChats(silent = false) }) {
                    Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Muted)
                }
                Box(Modifier.clip(CircleShape).clickable { model.openProfile() }) {
                    Avatar(state.username, state.photoUrl, 38)
                }
            }
            Column(Modifier.padding(horizontal = 20.dp)) {
                Text("Messages", color = TextMain, fontSize = 27.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(4.dp))
                Text(if (state.chats.isEmpty()) "Your private space starts here."
                    else "${state.chats.size} direct conversations", color = Muted, fontSize = 12.sp)
                Spacer(Modifier.height(17.dp))
                DarkField(state.search, model::setSearch, "Search conversations", leading = "⌕")
                Spacer(Modifier.height(15.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(color = Purple.copy(alpha = .17f), shape = RoundedCornerShape(20.dp)) {
                        Text("Chats", color = PurpleLight, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 15.dp, vertical = 8.dp))
                    }
                    Spacer(Modifier.width(9.dp))
                    TextButton(onClick = { showNewChat = true }) {
                        Icon(Icons.Default.Search, null, modifier = Modifier.size(15.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Find people", color = Muted, fontSize = 12.sp)
                    }
                    Spacer(Modifier.weight(1f))
                    Text("RECENT", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp)
                }
            }
            Spacer(Modifier.height(7.dp))
            when {
                state.loading && state.chats.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = PurpleLight, strokeWidth = 2.dp)
                }
                state.chats.isEmpty() -> EmptyState("No conversations yet",
                    "Find someone by username to start a private, encrypted conversation.",
                    "Find people") { showNewChat = true }
                state.filteredChats.isEmpty() -> EmptyState("No matches",
                    "Try a different username or clear your search.", null, null)
                else -> LazyColumn(Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 94.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.filteredChats, key = { it.id }) { chat ->
                        chat.peer(state.userId.orEmpty())?.let { peer -> ChatRow(chat, peer) { model.openChat(chat) } }
                    }
                }
            }
        }
    }
    if (showNewChat) NewChatDialog(model, { showNewChat = false })
}

@Composable
private fun BottomTabs(selected: AppPage, model: MainViewModel) {
    NavigationBar(containerColor = Panel, contentColor = Muted, tonalElevation = 0.dp) {
        NavigationBarItem(selected == AppPage.INBOX, { model.backToInbox() },
            icon = { Icon(Icons.Default.ChatBubbleOutline, null) }, label = { Text("Chats") }, colors = navColors())
        NavigationBarItem(selected == AppPage.PROFILE, { model.openProfile() },
            icon = { Icon(Icons.Default.PersonOutline, null) }, label = { Text("Me") }, colors = navColors())
        NavigationBarItem(selected == AppPage.SETTINGS, { model.openSettings() },
            icon = { Icon(Icons.Default.Tune, null) }, label = { Text("Settings") }, colors = navColors())
    }
}

@Composable
private fun navColors() = NavigationBarItemDefaults.colors(
    selectedIconColor = Color.White, selectedTextColor = Color.White,
    indicatorColor = Purple, unselectedIconColor = Muted, unselectedTextColor = Muted
)

@Composable
private fun ChatRow(chat: ChatSummary, peer: ChatUser, onClick: () -> Unit) {
    Surface(
        onClick = onClick, color = Panel, shape = RoundedCornerShape(20.dp), tonalElevation = 1.dp,
        border = androidx.compose.foundation.BorderStroke(1.dp, Line.copy(alpha = .48f))
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Avatar(peer.username, peer.photoUrl, 54)
            Spacer(Modifier.width(13.dp))
            Column(Modifier.weight(1f)) {
                Text("@${peer.username}", color = TextMain, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(5.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Lock, null, tint = Green, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(5.dp))
                    Text("End-to-end encrypted", color = Muted, fontSize = 11.sp, maxLines = 1)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(formatListTime(chat.updatedAt), color = Muted, fontSize = 10.sp)
                Spacer(Modifier.height(8.dp))
                Icon(Icons.Default.ChevronRight, null, tint = Muted, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun Avatar(username: String, photoUrl: String?, size: Int, online: Boolean = false) {
    val colors = listOf(Color(0xFF2766E8), Color(0xFF178A8A), Color(0xFF6C63C7),
        Color(0xFF3679A8), Color(0xFFAA714D), Color(0xFF5276B6))
    val color = colors[(username.hashCode().and(Int.MAX_VALUE)) % colors.size]
    var imageFailed by remember(photoUrl) { mutableStateOf(false) }
    Box(Modifier.size(size.dp)) {
        Box(Modifier.fillMaxSize().clip(CircleShape).background(color), contentAlignment = Alignment.Center) {
            Text(username.take(1).uppercase(), color = Color.White,
                fontSize = (size * .37f).sp, fontWeight = FontWeight.Bold)
        }
        if (!photoUrl.isNullOrBlank() && !imageFailed) {
            AsyncImage(model = photoUrl, contentDescription = "$username profile photo",
                contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(CircleShape),
                onError = { imageFailed = true })
        }
        if (online) Box(Modifier.align(Alignment.BottomEnd).size(13.dp).clip(CircleShape)
            .background(Green).border(2.dp, Ink, CircleShape))
    }
}

@Composable
private fun EmptyState(title: String, subtitle: String, action: String?, onAction: (() -> Unit)?) {
    Column(Modifier.fillMaxWidth().fillMaxHeight().padding(30.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(76.dp).clip(RoundedCornerShape(25.dp)).background(PanelRaised),
            contentAlignment = Alignment.Center) {
            Icon(Icons.Default.ChatBubbleOutline, null, tint = PurpleLight, modifier = Modifier.size(33.dp))
        }
        Spacer(Modifier.height(18.dp))
        Text(title, color = TextMain, fontSize = 19.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(7.dp))
        Text(subtitle, color = Muted, fontSize = 13.sp, lineHeight = 19.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (action != null && onAction != null) {
            Spacer(Modifier.height(19.dp))
            GradientButton(action, onClick = onAction)
        }
    }
}

@Composable
private fun NewChatDialog(model: MainViewModel, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<ChatUser>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    LaunchedEffect(query) {
        val term = query.trim().removePrefix("@")
        results = emptyList()
        if (term.length < 2 || !Regex("^[a-zA-Z0-9_]{2,20}$").matches(term)) searching = false
        else {
            searching = true
            kotlinx.coroutines.delay(350)
            model.searchUsers(term) { users ->
                if (query.trim().removePrefix("@").equals(term, ignoreCase = true)) {
                    results = users
                    searching = false
                }
            }
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = Panel, shape = RoundedCornerShape(25.dp),
        title = {
            Column {
                Text("Find someone", color = TextMain, fontWeight = FontWeight.ExtraBold, fontSize = 21.sp)
                Spacer(Modifier.height(5.dp))
                Text("Search by their CrazeChat username.", color = Muted, fontSize = 12.sp)
            }
        },
        text = {
            Column {
                DarkField(query, { query = it }, "Enter username", leading = "@")
                Spacer(Modifier.height(10.dp))
                when {
                    query.trim().removePrefix("@").length < 2 ->
                        Text("Enter at least 2 characters.", color = Muted, fontSize = 11.sp)
                    !Regex("^[a-zA-Z0-9_]{2,20}$").matches(query.trim().removePrefix("@")) ->
                        Text("Use 2–20 letters, numbers or underscores.", color = MaterialTheme.colorScheme.error, fontSize = 11.sp)
                    searching -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = PurpleLight, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    }
                    results.isEmpty() -> Text("No matching usernames found.", color = Muted, fontSize = 11.sp)
                    else -> results.forEach { user ->
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(15.dp))
                            .clickable { model.startChat(user.username); onDismiss() }
                            .padding(vertical = 10.dp, horizontal = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Avatar(user.username, user.photoUrl, 44)
                            Spacer(Modifier.width(11.dp))
                            Column(Modifier.weight(1f)) {
                                Text("@${user.username}", color = TextMain, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                                Text("Start an encrypted chat", color = Muted, fontSize = 11.sp)
                            }
                            Icon(Icons.Default.ChevronRight, null, tint = Muted)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close", color = PurpleLight) } }
    )
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun ChatPage(model: MainViewModel, state: CrazeUiState) {
    val chat = state.currentChat ?: return
    val context = LocalContext.current
    val listState = rememberLazyListState()
    var input by remember { mutableStateOf("") }
    var showFingerprint by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var selectedMessage by remember { mutableStateOf<UiMessage?>(null) }
    val peer = chat.peer(state.userId.orEmpty())
    val visibleMessages = remember(state.messages, state.chatSearch) {
        val q = state.chatSearch.trim().lowercase()
        if (q.isEmpty()) state.messages else state.messages.filter { it.text.lowercase().contains(q) }
    }
    LaunchedEffect(state.messages.size, state.chatSearch) {
        if (visibleMessages.isNotEmpty() && state.chatSearch.isBlank()) listState.animateScrollToItem(visibleMessages.lastIndex)
    }

    Column(Modifier.fillMaxSize().background(Ink)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = model::backFromChat) { Icon(Icons.Default.ArrowBack, null, tint = TextMain) }
            Avatar(peer?.username ?: "?", peer?.photoUrl, 43)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(peer?.username ?: "Conversation", color = TextMain, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                Text(if (state.keyVerified) "Verified contact key" else "Security check required",
                    color = if (state.keyVerified) Green else Color(0xFFFFBF69), fontSize = 11.sp)
            }
            IconButton(onClick = { showSearch = !showSearch }) { Icon(Icons.Default.Search, "Search messages", tint = Muted) }
            IconButton(onClick = { showFingerprint = true }) {
                Icon(if (state.keyVerified) Icons.Default.VerifiedUser else Icons.Default.Fingerprint,
                    "Contact fingerprint", tint = if (state.keyVerified) Green else PurpleLight)
            }
        }
        if (showSearch) {
            Box(Modifier.padding(horizontal = 14.dp)) { DarkField(state.chatSearch, model::setChatSearch, "Search in this conversation") }
            Spacer(Modifier.height(7.dp))
        }
        HorizontalDivider(color = Line.copy(alpha = .7f))
        if (!state.keyVerified) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)
                .clip(RoundedCornerShape(18.dp)).background(PanelRaised).padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Shield, null, tint = Color(0xFFFFBF69))
                    Spacer(Modifier.width(8.dp))
                    Text(if (state.peerKeyChanged) "Contact key changed" else "Verify this contact",
                        color = TextMain, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(7.dp))
                Text("Compare the SHA-256 fingerprint with your contact through a separate trusted channel. CrazeChat will not sync or send messages until you verify it.",
                    color = Muted, fontSize = 12.sp, lineHeight = 17.sp)
                Spacer(Modifier.height(9.dp))
                OutlinedButton(onClick = { showFingerprint = true }) { Text("View fingerprint", color = PurpleLight) }
            }
        }
        if (visibleMessages.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(28.dp)) {
                    Icon(Icons.Default.Lock, null, tint = PurpleLight, modifier = Modifier.size(34.dp))
                    Spacer(Modifier.height(10.dp))
                    Text(if (state.keyVerified) "No messages yet" else "Conversation protected",
                        color = TextMain, fontWeight = FontWeight.Bold)
                    Text(if (state.keyVerified) "Send a message to start this conversation."
                        else "Verify the contact fingerprint to load messages.", color = Muted, fontSize = 12.sp)
                }
            }
        } else {
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState,
                contentPadding = PaddingValues(horizontal = 15.dp, vertical = 15.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp)) {
                items(visibleMessages, key = { it.id }) { message -> MessageBubble(message) { selectedMessage = message } }
            }
        }
        state.replyTarget?.let { reply ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 4.dp)
                .clip(RoundedCornerShape(13.dp)).background(PanelRaised).padding(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(3.dp).height(34.dp).background(Purple, RoundedCornerShape(4.dp)))
                Spacer(Modifier.width(9.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (reply.senderId == state.userId) "Replying to you" else "Replying to @${state.peerName}",
                        color = PurpleLight, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    Text(reply.text, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 11.sp)
                }
                IconButton(onClick = model::clearReplyTarget) { Icon(Icons.Default.Close, "Cancel reply", tint = Muted) }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = input,
                onValueChange = { if (it.length <= 1500) input = it },
                enabled = state.keyVerified && !state.composing,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Message", color = Muted) },
                shape = RoundedCornerShape(23.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = Panel, unfocusedContainerColor = Panel,
                    disabledContainerColor = Panel, focusedBorderColor = Purple,
                    unfocusedBorderColor = Line, focusedTextColor = TextMain,
                    unfocusedTextColor = TextMain, disabledTextColor = Muted, cursorColor = Purple
                ),
                maxLines = 5
            )
            Spacer(Modifier.width(8.dp))
            IconButton(
                onClick = { model.sendMessage(input.trim()); input = "" },
                enabled = state.keyVerified && !state.composing && input.isNotBlank(),
                modifier = Modifier.size(50.dp).clip(CircleShape).background(Purple)
            ) {
                if (state.composing) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                else Icon(Icons.Default.Send, "Send message", tint = Color.White)
            }
        }
        Text("End-to-end encrypted on this device", color = Muted, fontSize = 10.sp,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 8.dp))
    }

    if (showFingerprint) {
        AlertDialog(
            onDismissRequest = { showFingerprint = false }, containerColor = Panel,
            title = { Text("Encryption fingerprint", color = TextMain) },
            text = {
                Column {
                    Text("Contact: @${state.peerName ?: "contact"}", color = Muted, fontSize = 12.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(state.peerFingerprint ?: "Fingerprint unavailable", color = TextMain, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(10.dp))
                    Text("Compare every group with your contact in person or through a separate trusted channel. A fingerprint sent only through this chat is not independent verification.",
                        color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
                }
            },
            confirmButton = {
                TextButton(onClick = { model.verifyPeerKey(); showFingerprint = false }, enabled = !state.keyVerified) {
                    Text(if (state.keyVerified) "Verified" else "I compared and verified", color = PurpleLight)
                }
            },
            dismissButton = { TextButton(onClick = { showFingerprint = false }) { Text("Close", color = Muted) } }
        )
    }
    selectedMessage?.let { message ->
        ModalBottomSheet(onDismissRequest = { selectedMessage = null }, containerColor = Panel) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 24.dp)) {
                Text("Message actions", color = TextMain, fontWeight = FontWeight.Bold, modifier = Modifier.padding(14.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                    listOf("❤️", "😂", "😮", "😢", "🙏", "👍").forEach { emoji ->
                        Text(emoji, modifier = Modifier.clip(CircleShape).clickable {
                            model.reactToMessage(message, emoji); selectedMessage = null
                        }.padding(9.dp), fontSize = 24.sp)
                    }
                }
                SheetAction(Icons.Default.Reply, "Reply") { model.setReplyTarget(message); selectedMessage = null }
                SheetAction(Icons.Default.ContentCopy, "Copy message") {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("CrazeChat message", message.text))
                    model.showInfoMessage("Message copied."); selectedMessage = null
                }
                if (message.mine) SheetAction(Icons.Default.DeleteOutline, "Delete message", color = MaterialTheme.colorScheme.error) {
                    model.deleteMessage(message); selectedMessage = null
                }
            }
        }
    }
}

@Composable
private fun SheetAction(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, color: Color = TextMain, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = color)
        Spacer(Modifier.width(13.dp))
        Text(title, color = color, fontWeight = FontWeight.SemiBold)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(message: UiMessage, onLongClick: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (message.mine) Alignment.End else Alignment.Start) {
        Column(
            Modifier.widthIn(max = 320.dp).clip(
                if (message.mine) RoundedCornerShape(20.dp, 20.dp, 6.dp, 20.dp)
                else RoundedCornerShape(20.dp, 20.dp, 20.dp, 6.dp)
            ).background(
                if (message.mine) Brush.horizontalGradient(listOf(Color(0xFF2367F4), Color(0xFF3987FF)))
                else Brush.linearGradient(listOf(PanelRaised, PanelRaised))
            ).combinedClickable(onClick = {}, onLongClick = onLongClick)
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            message.replyTo?.let { reply ->
                Row(Modifier.fillMaxWidth().padding(bottom = 7.dp), verticalAlignment = Alignment.Top) {
                    Box(Modifier.width(3.dp).height(32.dp).background(Color.White.copy(alpha = .78f), RoundedCornerShape(4.dp)))
                    Spacer(Modifier.width(7.dp))
                    Column {
                        Text("Reply", color = Color.White.copy(alpha = .8f), fontSize = 9.sp, fontWeight = FontWeight.Bold)
                        Text(reply.text, color = Color.White.copy(alpha = .78f), maxLines = 2,
                            overflow = TextOverflow.Ellipsis, fontSize = 11.sp)
                    }
                }
            }
            Text(message.text, color = if (message.mine) Color.White else TextMain, fontSize = 14.sp, lineHeight = 20.sp)
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.End) {
                Text(formatClock(message.createdAt), color = if (message.mine) Color.White.copy(alpha = .68f) else Muted, fontSize = 9.sp)
                if (message.mine) {
                    Spacer(Modifier.width(4.dp))
                    Text(when (message.deliveryState) { "queued" -> "◷"; "read" -> "✓✓"; "delivered" -> "✓✓"; else -> "✓" },
                        color = Color.White.copy(alpha = .9f), fontSize = 10.sp)
                }
            }
        }
        if (message.reactions.isNotEmpty()) {
            Row(Modifier.padding(top = 3.dp).clip(RoundedCornerShape(12.dp)).background(Panel)
                .padding(horizontal = 7.dp, vertical = 3.dp)) {
                message.reactions.values.groupingBy { it }.eachCount().forEach { (emoji, count) ->
                    Text(if (count > 1) "$emoji $count" else emoji, color = TextMain, fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 2.dp))
                }
            }
        }
    }
}

@Composable
private fun ProfilePage(model: MainViewModel, state: CrazeUiState) {
    var editPhoto by remember { mutableStateOf(false) }
    var photoUrl by remember(state.photoUrl) { mutableStateOf(state.photoUrl.orEmpty()) }
    val context = LocalContext.current
    Scaffold(containerColor = Ink, bottomBar = { BottomTabs(AppPage.PROFILE, model) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("Your profile", color = TextMain, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier.weight(1f))
                IconButton(onClick = model::openSettings) { Icon(Icons.Default.Settings, "Settings", tint = Muted) }
            }
            Surface(color = Panel, shape = RoundedCornerShape(26.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, Line.copy(alpha = .6f))) {
                Column(Modifier.fillMaxWidth().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(118.dp).clip(CircleShape).border(3.dp, Purple.copy(alpha = .5f), CircleShape),
                        contentAlignment = Alignment.Center) { Avatar(state.username, state.photoUrl, 112) }
                    Spacer(Modifier.height(14.dp))
                    Text("@${state.username}", color = TextMain, fontSize = 23.sp, fontWeight = FontWeight.ExtraBold)
                    Text("CrazeChat member", color = Muted, fontSize = 12.sp)
                    Spacer(Modifier.height(18.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                        Button(onClick = { editPhoto = true }, modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = Purple), shape = RoundedCornerShape(14.dp)) {
                            Icon(Icons.Default.Edit, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp)); Text("Edit photo")
                        }
                        OutlinedButton(onClick = {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, "Find me on CrazeChat: @${state.username}")
                            }
                            context.startActivity(Intent.createChooser(sendIntent, "Share CrazeChat profile"))
                        }, modifier = Modifier.weight(1f),
                            border = androidx.compose.foundation.BorderStroke(1.dp, Line), shape = RoundedCornerShape(14.dp)) {
                            Icon(Icons.Default.Share, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp)); Text("Share")
                        }
                    }
                }
            }
            Spacer(Modifier.height(19.dp))
            SectionLabel("ACCOUNT")
            SettingsRow(Icons.Default.AlternateEmail, "Username", "@${state.username}") {}
            SettingsRow(Icons.Default.Security, "Encryption", "X25519 · end-to-end encrypted") {}
            SettingsRow(Icons.Default.ChatBubbleOutline, "Direct conversations", state.chats.size.toString()) {}
            Spacer(Modifier.height(19.dp))
            Text("Your profile photo URL is shared with people you chat with.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
            Spacer(Modifier.height(20.dp))
        }
    }
    if (editPhoto) {
        AlertDialog(
            onDismissRequest = { editPhoto = false }, containerColor = Panel, shape = RoundedCornerShape(23.dp),
            title = { Text("Profile photo", color = TextMain) },
            text = {
                Column {
                    Text("Paste a direct HTTPS image URL. This link is saved to your CrazeChat profile and shown to your chat partner.",
                        color = Muted, fontSize = 12.sp, lineHeight = 17.sp)
                    Spacer(Modifier.height(12.dp))
                    DarkField(photoUrl, { photoUrl = it }, "https://example.com/photo.jpg")
                    Spacer(Modifier.height(7.dp))
                    Text("Use a public image link that does not require sign-in.", color = Muted, fontSize = 10.sp)
                }
            },
            confirmButton = {
                TextButton(onClick = { model.updateProfilePhoto(photoUrl.takeIf(String::isNotBlank)); editPhoto = false }) {
                    Text("Save", color = PurpleLight)
                }
            },
            dismissButton = {
                TextButton(onClick = { photoUrl = ""; model.updateProfilePhoto(null); editPhoto = false }) {
                    Text("Remove photo", color = MaterialTheme.colorScheme.error)
                }
            }
        )
    }
}

@Composable
private fun SettingsPage(model: MainViewModel, state: CrazeUiState) {
    var showLogout by remember { mutableStateOf(false) }
    var showPassword by remember { mutableStateOf(false) }
    var showAccounts by remember { mutableStateOf(false) }
    val activity = LocalContext.current as? MainActivity
    Scaffold(containerColor = Ink, bottomBar = { BottomTabs(AppPage.SETTINGS, model) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 19.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                Text("Settings", color = TextMain, fontSize = 29.sp, fontWeight = FontWeight.ExtraBold)
                Text("Make CrazeChat work the way you do.", color = Muted, fontSize = 12.sp)
                Spacer(Modifier.height(10.dp))
                Surface(onClick = { model.openProfile() }, color = Panel, shape = RoundedCornerShape(20.dp),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Line.copy(alpha = .55f))) {
                    Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(state.username, state.photoUrl, 50)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("@${state.username}", color = TextMain, fontWeight = FontWeight.Bold)
                            Text("Manage your profile", color = Muted, fontSize = 11.sp)
                        }
                        Icon(Icons.Default.ChevronRight, null, tint = Muted)
                    }
                }
            }
            item { SectionLabel("ACCOUNT") }
            item { SettingsRow(Icons.Default.Password, "Change password", "Update your CrazeChat account password") { showPassword = true } }
            item { SettingsRow(Icons.Default.Lock, "Lock CrazeChat now", "Require your account password to unlock this device") { model.lock() } }
            item { SettingsRow(Icons.Default.Fingerprint, "Privacy and security", "Encryption and contact-key verification") { model.openPrivacy() } }
            item { SectionLabel("NOTIFICATIONS") }
            item { SettingSwitch(Icons.Default.Notifications, "Push notifications",
                "Generic alerts for new encrypted messages", state.notificationsEnabled) { model.setNotificationsEnabled(it) } }
            item { SettingSwitch(Icons.Default.VolumeUp, "Sound effects",
                "Play short feedback sounds for message events", state.soundEffectsEnabled, model::setSoundEffectsEnabled) }
            item { SettingSwitch(Icons.Default.Vibration, "Vibration",
                "Use haptic feedback for incoming and outgoing messages", state.vibrationEnabled, model::setVibrationEnabled) }
            item { SectionLabel("APPEARANCE") }
            item {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(15.dp)) {
                    Text("Theme", color = TextMain, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(10.dp))
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf("system" to "System", "light" to "Light", "dark" to "Dark").forEachIndexed { index, choice ->
                            SegmentedButton(selected = state.themeMode == choice.first,
                                onClick = { model.setThemeMode(choice.first) },
                                shape = SegmentedButtonDefaults.itemShape(index, 3)) { Text(choice.second) }
                        }
                    }
                }
            }
            item { SectionLabel("LOCAL DATA") }
            item { SettingSwitch(Icons.Default.VisibilityOff, "Block screenshots",
                "Hide app content from screenshots and recent-app previews", state.screenSecureEnabled) { enabled ->
                    model.setScreenSecure(enabled); activity?.setScreenSecure(enabled)
                }
            }
            item {
                LocalFolderSyncCard(state = state,
                    onChoose = { activity?.chooseSyncFolder { uri -> if (uri != null) model.setLocalFolder(uri) } },
                    onSync = model::syncNow)
            }
            item { SettingsRow(Icons.Default.Storage, "Storage and data", formatBytes(state.storageBytes)) { model.openStorage() } }
            item { SectionLabel("ACCOUNTS") }
            item { SettingsRow(Icons.Default.SwitchAccount, "Switch account", "Manage saved accounts on this device") { showAccounts = true } }
            item { SettingsRow(Icons.Default.PersonAddAlt1, "Add account", "Sign in with another CrazeChat account") { model.addAccount() } }
            item {
                Spacer(Modifier.height(5.dp))
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel)
                    .clickable { showLogout = true }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Logout, null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(12.dp))
                    Text("Sign out", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(10.dp))
            }
        }
    }
    if (showLogout) {
        AlertDialog(onDismissRequest = { showLogout = false }, containerColor = Panel,
            title = { Text("Sign out of CrazeChat?", color = TextMain) },
            text = { Text("This removes this account's local session and saved identity key from this device. Keep an encrypted folder backup if you need to restore your message archive.", color = Muted) },
            confirmButton = {
                TextButton(onClick = { showLogout = false; model.signOut() }) {
                    Text("Sign out", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showLogout = false }) { Text("Cancel", color = Muted) } }
        )
    }
    if (showPassword) ChangePasswordDialog(model) { showPassword = false }
    if (showAccounts) AccountsDialog(state.savedAccounts, state.userId, model) { showAccounts = false }
}

@Composable
private fun ChangePasswordDialog(model: MainViewModel, onDismiss: () -> Unit) {
    var current by remember { mutableStateOf("") }
    var next by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        title = { Text("Change password", color = TextMain) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                Text("Your identity key is automatically re-encrypted with the new account password. No separate encryption phrase is needed.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
                DarkField(current, { current = it }, "Current password", password = true)
                DarkField(next, { next = it }, "New password (12+ characters)", password = true)
                DarkField(confirm, { confirm = it }, "Confirm new password", password = true)
            }
        },
        confirmButton = {
            TextButton(onClick = { model.changePassword(current, next, confirm); onDismiss() }) {
                Text("Update", color = PurpleLight)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = Muted) } }
    )
}

@Composable
private fun AccountsDialog(accounts: List<SavedAccount>, currentId: String?, model: MainViewModel, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        title = { Text("Saved accounts", color = TextMain) },
        text = {
            Column {
                val others = accounts.filter { it.userId != currentId }
                if (others.isEmpty()) Text("No other account saved on this device.", color = Muted, fontSize = 12.sp)
                others.forEach { account ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                            .clickable { model.switchAccount(account.userId); onDismiss() }.padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Avatar(account.username, account.photoUrl, 42)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text("@${account.username}", color = TextMain, fontWeight = FontWeight.SemiBold)
                            Text("Switch account", color = Muted, fontSize = 11.sp)
                        }
                        Icon(Icons.Default.ChevronRight, null, tint = Muted)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close", color = PurpleLight) } },
        dismissButton = { TextButton(onClick = { model.addAccount(); onDismiss() }) { Text("Add account", color = Muted) } }
    )
}

@Composable
private fun LocalFolderSyncCard(state: CrazeUiState, onChoose: () -> Unit, onSync: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp)).background(Panel).padding(15.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SettingIcon(Icons.Default.Folder)
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f)) {
                Text("Local Folder Sync", color = TextMain, fontWeight = FontWeight.Bold)
                Text(if (state.localFolderSelected) "Encrypted backup folder selected" else "Choose a folder for your encrypted archive", color = Muted, fontSize = 10.sp)
            }
            if (state.localSyncing) CircularProgressIndicator(Modifier.size(18.dp), color = PurpleLight, strokeWidth = 2.dp)
        }
        Spacer(Modifier.height(8.dp))
        Text("The selected folder stores an identity-key-encrypted archive of message envelopes and deletion markers, not plaintext messages.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
        state.lastSyncAt?.let {
            Spacer(Modifier.height(8.dp))
            Text("Last saved: ${formatListTime(it)}", color = Muted, fontSize = 10.sp)
        }
        state.localSyncStatus?.let {
            Spacer(Modifier.height(7.dp))
            Text(it, color = PurpleLight, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onChoose, enabled = !state.localSyncing) {
                Icon(Icons.Default.FolderOpen, null); Spacer(Modifier.width(6.dp))
                Text(if (state.localFolderSelected) "Change folder" else "Choose folder")
            }
            if (state.localFolderSelected) {
                Button(onClick = onSync, enabled = !state.localSyncing, colors = ButtonDefaults.buttonColors(containerColor = Purple)) {
                    Icon(Icons.Default.Sync, null); Spacer(Modifier.width(6.dp)); Text("Sync now")
                }
            }
        }
    }
}

@Composable
private fun SettingSwitch(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp)).background(Panel).padding(horizontal = 15.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingIcon(icon)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = TextMain, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = Muted, fontSize = 10.sp)
        }
        Switch(checked = checked, onCheckedChange = onChecked, colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Purple))
    }
}

@Composable
private fun SettingsRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp)).background(Panel).clickable(onClick = onClick).padding(horizontal = 15.dp, vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingIcon(icon)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = TextMain, fontWeight = FontWeight.SemiBold)
            if (subtitle.isNotBlank()) Text(subtitle, color = Muted, fontSize = 11.sp, lineHeight = 15.sp)
        }
        Icon(Icons.Default.ChevronRight, null, tint = Muted, modifier = Modifier.size(19.dp))
    }
}

@Composable
private fun SettingIcon(icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(Purple.copy(alpha = .16f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = PurpleLight)
    }
}

@Composable
private fun PrivacyPage(model: MainViewModel, state: CrazeUiState) {
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = model::openSettings) { Icon(Icons.Default.ArrowBack, null, tint = TextMain) }
            Column {
                Text("Privacy & security", color = TextMain, fontSize = 23.sp, fontWeight = FontWeight.ExtraBold)
                Text("How CrazeChat protects your conversations", color = Muted, fontSize = 11.sp)
            }
        }
        Spacer(Modifier.height(14.dp))
        SecurityCard(Icons.Default.Lock, "Encrypted local vault",
            "Session data and cached message envelopes use AES-256-GCM with a key held by Android Keystore.")
        SecurityCard(Icons.Default.Fingerprint, "Contact-key verification",
            "A contact's X25519 fingerprint must be compared outside the chat. Remote sync and sending stay blocked until it is verified.")
        SecurityCard(Icons.Default.Shield, "End-to-end message encryption",
            "X25519 key agreement, HKDF-SHA256 and AES-256-GCM encrypt message content on this device. The server stores encrypted message envelopes.")
        SecurityCard(Icons.Default.Security, "Network protection",
            "CrazeChat requires HTTPS for non-local API origins, disables HTTP redirects and uses per-account authenticated sessions.")
        SecurityCard(Icons.Default.Info, "Device security",
            "Android Keystore protects stored keys at rest. A rooted or compromised device may still access secrets while the app is unlocked.")
        Spacer(Modifier.height(10.dp))
        GradientButton("Lock CrazeChat") { model.lock() }
    }
}

@Composable
private fun SecurityCard(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, body: String) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp).clip(RoundedCornerShape(17.dp)).background(Panel).padding(15.dp),
        verticalAlignment = Alignment.Top
    ) {
        SettingIcon(icon)
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, color = TextMain, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(5.dp))
            Text(body, color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
        }
    }
}

@Composable
private fun StoragePage(model: MainViewModel, state: CrazeUiState) {
    Column(Modifier.fillMaxSize().padding(22.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = model::openSettings) { Icon(Icons.Default.ArrowBack, null, tint = TextMain) }
            Text("Storage and data", color = TextMain, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(25.dp))
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Panel).padding(23.dp)) {
            Column {
                Text("ENCRYPTED LOCAL VAULT", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(formatBytes(state.storageBytes), color = TextMain, fontSize = 31.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(6.dp))
                Text("Stored locally on this device. This does not include the Android app installation size.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
            }
        }
        Spacer(Modifier.height(15.dp))
        SecurityCard(Icons.Default.Storage, "Encrypted cache", "Received message envelopes are saved locally before the server is asked to remove the read copy. The local vault is protected by Android Keystore.")
        SecurityCard(Icons.Default.WarningAmber, "Device loss", "Uninstalling the app or clearing its data removes the local vault. Use the optional encrypted folder sync in Settings to keep a separate archive.")
        Spacer(Modifier.weight(1f))
        OutlinedButton(onClick = model::updateStorageCount, modifier = Modifier.fillMaxWidth(), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) {
            Icon(Icons.Default.Refresh, null); Spacer(Modifier.width(8.dp)); Text("Refresh storage")
        }
    }
}

@Composable
private fun SectionLabel(label: String) {
    Text(label, color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, modifier = Modifier.padding(top = 10.dp, bottom = 6.dp))
}

private fun formatListTime(timestamp: Long): String {
    if (timestamp <= 0) return ""
    val date = Date(timestamp)
    val now = Date()
    val sameDay = SimpleDateFormat("yyyyMMdd", Locale.getDefault()).format(date) ==
        SimpleDateFormat("yyyyMMdd", Locale.getDefault()).format(now)
    return if (sameDay) SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)
    else SimpleDateFormat("dd MMM", Locale.getDefault()).format(date)
}

private fun formatClock(timestamp: Long): String =
    if (timestamp <= 0) "" else SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))

private fun formatBytes(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> String.format(Locale.getDefault(), "%.1f KB", bytes / 1024.0)
    else -> String.format(Locale.getDefault(), "%.2f MB", bytes / (1024.0 * 1024.0))
}
