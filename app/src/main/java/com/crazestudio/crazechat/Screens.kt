package com.crazestudio.crazechat

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val Ink = Color(0xFF0F0D16)
private val Panel = Color(0xFF1B1927)
private val PanelRaised = Color(0xFF242132)
private val Purple = Color(0xFF7444FA)
private val PurpleLight = Color(0xFFB23CEB)
private val Muted = Color(0xFFA6A1B6)
private val Green = Color(0xFF27D69B)
private val Line = Color(0xFF302D40)
private val TextMain = Color(0xFFF7F5FC)

@Composable
fun CrazeChatRoot(model: MainViewModel = viewModel()) {
    val state by model.state.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(state.error) {
        state.error?.let { snackbar.showSnackbar(it); model.consumeMessage() }
    }
    LaunchedEffect(state.info) {
        state.info?.let { snackbar.showSnackbar(it); model.consumeMessage() }
    }

    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Purple,
            onPrimary = Color.White,
            secondary = PurpleLight,
            background = Ink,
            surface = Panel,
            surfaceVariant = PanelRaised,
            onSurface = TextMain,
            onSurfaceVariant = Muted,
            outline = Line,
            error = Color(0xFFFF6B81)
        )
    ) {
        Box(Modifier.fillMaxSize().background(Ink)) {
            if (!state.ready) {
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    BrandMark(66)
                    Spacer(Modifier.height(20.dp))
                    CircularProgressIndicator(color = PurpleLight, strokeWidth = 2.dp)
                }
            } else when {
                state.page == AppPage.AUTH && state.userId != null ->
                    UnlockPage(model, state)
                state.page == AppPage.AUTH -> AuthPage(model, state)
                state.page == AppPage.INBOX -> InboxPage(model, state)
                state.page == AppPage.CHAT -> ChatPage(model, state)
                state.page == AppPage.PROFILE -> ProfilePage(model, state)
                state.page == AppPage.SETTINGS -> SettingsPage(model, state)
                state.page == AppPage.PRIVACY -> PrivacyPage(model, state)
                state.page == AppPage.STORAGE -> StoragePage(model, state)
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
            .background(Brush.linearGradient(listOf(Purple, PurpleLight))),
        contentAlignment = Alignment.Center
    ) {
        Text("ϟ", color = Color.White, fontSize = (size * .62f).sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun BrandTitle(size: Int = 24) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        BrandMark(36)
        Spacer(Modifier.width(10.dp))
        Text("CrazeChat", color = TextMain, fontSize = size.sp, fontWeight = FontWeight.ExtraBold)
    }
}

@Composable
private fun AuthPage(model: MainViewModel, state: CrazeUiState) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passphrase by remember { mutableStateOf("") }
    val signup = state.signup

    Column(
        Modifier.fillMaxSize().imePadding().background(Ink).padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.Start
    ) {
        Spacer(Modifier.height(28.dp))
        BrandMark(68)
        Spacer(Modifier.height(27.dp))
        Text(if (signup) "Join CrazeChat" else "CrazeChat", color = TextMain, fontSize = 32.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(6.dp))
        Text(
            if (signup) "Create your private account." else "Conversations with energy. Welcome back.",
            color = Muted, fontSize = 15.sp
        )
        Spacer(Modifier.height(28.dp))
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(4.dp)) {
            AuthTab("Log in", !signup, Modifier.weight(1f)) { model.setSignup(false) }
            AuthTab("Sign up", signup, Modifier.weight(1f)) { model.setSignup(true) }
        }
        Spacer(Modifier.height(22.dp))
        FormLabel("Username")
        DarkField(username, { username = it }, "your_username", leading = "@" )
        Spacer(Modifier.height(15.dp))
        FormLabel("Password")
        DarkField(password, { password = it }, if (signup) "At least 12 characters" else "Your account password", password = true)
        Spacer(Modifier.height(15.dp))
        FormLabel(if (signup) "Encryption passphrase" else "Encryption passphrase (new device)")
        DarkField(
            passphrase, { passphrase = it },
            if (signup) "Different from your account password" else "Enter if this device has no saved key",
            password = true
        )
        if (signup) {
            Spacer(Modifier.height(8.dp))
            Text("This separate passphrase protects your private identity key. It is never sent to the server. Keep it safe.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
        } else {
            Spacer(Modifier.height(6.dp))
            Text("Leave this blank on a device that already has your saved identity key. Legacy accounts may use the account password.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
        }
        Spacer(Modifier.height(22.dp))
        GradientButton(if (signup) "Create account" else "Log in") {
            model.authenticate(username, password, passphrase, signup)
        }
        Spacer(Modifier.height(22.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            HorizontalDivider(Modifier.weight(1f), color = Line)
            Text("  PRIVATE BY DESIGN  ", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            HorizontalDivider(Modifier.weight(1f), color = Line)
        }
        Spacer(Modifier.height(17.dp))
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Shield, contentDescription = null, tint = PurpleLight, modifier = Modifier.size(19.dp))
            Spacer(Modifier.width(9.dp))
            Text("Your messages are encrypted on your device before they are sent. The server stores encrypted message envelopes, not readable message text.", color = Muted, fontSize = 11.sp, lineHeight = 16.sp)
        }
        Spacer(Modifier.weight(1f))
        Text("By continuing, you agree to the CrazeChat Terms and Privacy Policy.", color = Muted, fontSize = 10.sp, lineHeight = 15.sp)
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
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = singleLine,
        placeholder = { Text(hint, color = Muted.copy(alpha = .78f), fontSize = 14.sp) },
        leadingIcon = if (leading != null) ({ Text(leading, color = Muted, fontSize = 18.sp) }) else null,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = if (password) KeyboardOptions(keyboardType = KeyboardType.Password) else KeyboardOptions.Default,
        shape = RoundedCornerShape(17.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = Panel,
            unfocusedContainerColor = Panel,
            focusedBorderColor = Purple,
            unfocusedBorderColor = Line,
            focusedTextColor = TextMain,
            unfocusedTextColor = TextMain,
            cursorColor = PurpleLight
        )
    )
}

@Composable
private fun GradientButton(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(17.dp))
            .background(Brush.horizontalGradient(listOf(Purple, PurpleLight)))
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier.background(Line)),
        contentAlignment = Alignment.Center
    ) { Text(label, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp) }
}

@Composable
private fun UnlockPage(model: MainViewModel, state: CrazeUiState) {
    var passphrase by remember { mutableStateOf("") }
    Column(
        Modifier.fillMaxSize().imePadding().padding(28.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.Center
    ) {
        BrandMark(64)
        Spacer(Modifier.height(24.dp))
        Text("Welcome back, @${state.username}", color = TextMain, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
        Spacer(Modifier.height(8.dp))
        Text("Unlock your private identity key to open your conversations.", color = Muted, fontSize = 14.sp)
        Spacer(Modifier.height(24.dp))
        FormLabel("Encryption passphrase")
        DarkField(passphrase, { passphrase = it }, "Your private-key passphrase", password = true)
        Spacer(Modifier.height(18.dp))
        GradientButton("Unlock CrazeChat") { model.unlock(passphrase) }
        TextButton(onClick = { model.signOut() }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text("Sign in to another account", color = Muted)
        }
    }
}

@Composable
private fun InboxPage(model: MainViewModel, state: CrazeUiState) {
    var showNewChat by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    Scaffold(
        containerColor = Ink,
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showNewChat = true },
                containerColor = Purple,
                contentColor = Color.White,
                shape = RoundedCornerShape(20.dp)
            ) { Icon(Icons.Default.Edit, contentDescription = "New chat") }
        },
        bottomBar = { BottomTabs(AppPage.INBOX, model) }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(
                Modifier.fillMaxWidth().padding(start = 22.dp, end = 18.dp, top = 17.dp, bottom = 18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BrandTitle(23)
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { showSearch = !showSearch }) {
                    Icon(Icons.Default.Search, contentDescription = "Search", tint = TextMain)
                }
            }
            if (showSearch) {
                DarkField(state.search, model::setSearch, "Search conversations")
                Spacer(Modifier.height(12.dp))
            }
            Text("YOUR CONVERSATIONS", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp, modifier = Modifier.padding(horizontal = 24.dp))
            Spacer(Modifier.height(12.dp))
            val contacts = state.chats.mapNotNull { it.peer(state.userId.orEmpty()) }.distinctBy { it.id }.take(8)
            if (contacts.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().height(82.dp).padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    contacts.forEach { peer ->
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(54.dp)) {
                            Avatar(peer.username, peer.photoUrl, 48)
                            Spacer(Modifier.height(4.dp))
                            Text(peer.username.take(9), color = Muted, fontSize = 10.sp, maxLines = 1)
                        }
                    }
                }
            } else {
                Spacer(Modifier.height(12.dp))
            }
            Row(
                Modifier.padding(horizontal = 22.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(9.dp)
            ) {
                FilterChip(selected = !state.unreadOnly, onClick = { model.setUnreadOnly(false) }, label = { Text("All") })
                FilterChip(selected = false, onClick = { model.showInfo("Unread status is not exposed by the current CrazeChat API yet.") }, label = { Text("Unread") })
                FilterChip(selected = false, onClick = { model.showInfo("Group conversations are not available in the current CrazeChat backend.") }, label = { Text("Groups") })
            }
            if (state.chats.isEmpty() && !state.loading) {
                EmptyState(
                    title = "Your chats start here",
                    subtitle = "Find a CrazeChat username and start an end-to-end encrypted conversation.",
                    action = "Start a chat",
                    onAction = { showNewChat = true }
                )
            } else if (state.filteredChats.isEmpty() && !state.loading) {
                EmptyState("No conversations found", "Try a different search or switch to All.", null, null)
            } else {
                LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 90.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    items(state.filteredChats, key = { it.id }) { chat ->
                        val peer = chat.peer(state.userId.orEmpty())
                        if (peer != null) ChatRow(chat, peer) { model.openChat(chat) }
                    }
                }
            }
        }
    }
    if (showNewChat) NewChatDialog(model, { showNewChat = false })
}

@Composable
private fun BottomTabs(selected: AppPage, model: MainViewModel) {
    NavigationBar(containerColor = Panel, contentColor = Muted) {
        NavigationBarItem(
            selected = selected == AppPage.INBOX,
            onClick = { model.backToInbox() },
            icon = { Icon(Icons.Default.ChatBubbleOutline, null) },
            label = { Text("Chats") },
            colors = navColors()
        )
        NavigationBarItem(
            selected = selected == AppPage.PROFILE,
            onClick = { model.openProfile() },
            icon = { Icon(Icons.Default.PersonOutline, null) },
            label = { Text("Profile") },
            colors = navColors()
        )
        NavigationBarItem(
            selected = selected == AppPage.SETTINGS,
            onClick = { model.openSettings() },
            icon = { Icon(Icons.Default.Tune, null) },
            label = { Text("Settings") },
            colors = navColors()
        )
    }
}

@Composable
private fun navColors() = NavigationBarItemDefaults.colors(
    selectedIconColor = Color.White,
    selectedTextColor = Color.White,
    indicatorColor = Purple.copy(alpha = .35f),
    unselectedIconColor = Muted,
    unselectedTextColor = Muted
)

@Composable
private fun ChatRow(chat: ChatSummary, peer: ChatUser, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Ink)
            .clickable(onClick = onClick).padding(vertical = 11.dp, horizontal = 3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Avatar(peer.username, peer.photoUrl, 55)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(peer.username, color = TextMain, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text("End-to-end encrypted conversation", color = Muted, fontSize = 11.sp, maxLines = 1)
        }
        Text(formatListTime(chat.updatedAt), color = Muted, fontSize = 11.sp)
    }
}

@Composable
private fun Avatar(username: String, photoUrl: String?, size: Int, online: Boolean = false) {
    val colors = listOf(Color(0xFFB30F64), Color(0xFF087B70), Color(0xFF7526BE), Color(0xFF087AA8), Color(0xFFB9572A), Color(0xFF6552C9))
    val color = colors[(username.hashCode().and(Int.MAX_VALUE)) % colors.size]
    Box(Modifier.size(size.dp)) {
        if (!photoUrl.isNullOrBlank()) {
            AsyncImage(
                model = photoUrl, contentDescription = "$username profile photo",
                modifier = Modifier.fillMaxSize().clip(CircleShape)
            )
        } else {
            Box(Modifier.fillMaxSize().clip(CircleShape).background(color), contentAlignment = Alignment.Center) {
                Text(username.take(1).uppercase(), color = Color.White, fontSize = (size * .37f).sp, fontWeight = FontWeight.Bold)
            }
        }
        if (online) Box(
            Modifier.align(Alignment.BottomEnd).size(13.dp).clip(CircleShape)
                .background(Green).border(2.dp, Ink, CircleShape)
        )
    }
}

@Composable
private fun EmptyState(title: String, subtitle: String, action: String?, onAction: (() -> Unit)?) {
    Column(
        Modifier.fillMaxWidth().fillMaxHeight().padding(30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(Modifier.size(68.dp).clip(CircleShape).background(Panel), contentAlignment = Alignment.Center) {
            Icon(Icons.Default.ChatBubbleOutline, null, tint = PurpleLight, modifier = Modifier.size(30.dp))
        }
        Spacer(Modifier.height(17.dp))
        Text(title, color = TextMain, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(7.dp))
        Text(subtitle, color = Muted, fontSize = 13.sp, lineHeight = 19.sp)
        if (action != null && onAction != null) {
            Spacer(Modifier.height(18.dp))
            GradientButton(action, onClick = onAction)
        }
    }
}

@Composable
private fun NewChatDialog(model: MainViewModel, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<ChatUser>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        title = { Text("Find people", color = TextMain, fontWeight = FontWeight.Bold) },
        text = {
            Column {
                DarkField(query, {
                    query = it
                    if (it.trim().length >= 2) {
                        searching = true
                        scope.launch {
                            kotlinx.coroutines.delay(250)
                            model.searchUsers(it) { users ->
                                results = users
                                searching = false
                            }
                        }
                    } else results = emptyList()
                }, "Search by username")
                Spacer(Modifier.height(10.dp))
                if (searching) CircularProgressIndicator(color = PurpleLight, modifier = Modifier.align(Alignment.CenterHorizontally))
                results.forEach { user ->
                    Row(
                        Modifier.fillMaxWidth().clickable { model.startChat(user.username); onDismiss() }.padding(vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Avatar(user.username, user.photoUrl, 42)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("@${user.username}", color = TextMain, fontWeight = FontWeight.SemiBold)
                            Text("Start a private chat", color = Muted, fontSize = 11.sp)
                        }
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Default.ChevronRight, null, tint = Muted)
                    }
                }
                if (!searching && query.length >= 2 && results.isEmpty()) {
                    Text("No matching users found.", color = Muted, fontSize = 12.sp)
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close", color = PurpleLight) } }
    )
}

@Composable
private fun ChatPage(model: MainViewModel, state: CrazeUiState) {
    val chat = state.currentChat ?: return
    val listState = rememberLazyListState()
    var input by remember { mutableStateOf("") }
    var showFingerprint by remember { mutableStateOf(false) }
    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) listState.animateScrollToItem(state.messages.lastIndex)
    }
    Column(Modifier.fillMaxSize().background(Ink)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = model::backFromChat) { Icon(Icons.Default.ArrowBack, null, tint = TextMain) }
            val peer = chat.peer(state.userId.orEmpty())
            Avatar(peer?.username ?: "?", peer?.photoUrl, 42)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(peer?.username ?: "Conversation", color = TextMain, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                Text(if (state.keyVerified) "Contact key verified" else "Verify encryption key", color = if (state.keyVerified) Green else Color(0xFFFFC06B), fontSize = 11.sp)
            }
            IconButton(onClick = { showFingerprint = true }) {
                Icon(if (state.keyVerified) Icons.Default.VerifiedUser else Icons.Default.Fingerprint, null, tint = if (state.keyVerified) Green else PurpleLight)
            }
        }
        HorizontalDivider(color = Line)
        if (!state.keyVerified) {
            Column(Modifier.fillMaxWidth().padding(18.dp).clip(RoundedCornerShape(16.dp)).background(Panel).padding(15.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Shield, null, tint = Color(0xFFFFC06B))
                    Spacer(Modifier.width(8.dp))
                    Text("Verify this contact", color = TextMain, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(7.dp))
                Text("Compare the SHA-256 fingerprint with your contact over a separate trusted channel. New messages will not sync or send until you verify it.", color = Muted, fontSize = 12.sp, lineHeight = 17.sp)
                Spacer(Modifier.height(10.dp))
                OutlinedButton(onClick = { showFingerprint = true }, border = androidx.compose.foundation.BorderStroke(1.dp, Purple)) {
                    Text("View fingerprint", color = PurpleLight)
                }
            }
        }
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth(),
            state = listState,
            contentPadding = PaddingValues(horizontal = 15.dp, vertical = 15.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            items(state.messages, key = { it.id }) { message ->
                MessageBubble(message)
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            Box(Modifier.size(46.dp).clip(CircleShape).background(Panel), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Add, null, tint = Muted)
            }
            Spacer(Modifier.width(8.dp))
            OutlinedTextField(
                value = input,
                onValueChange = { if (it.length <= 1500) input = it },
                enabled = state.keyVerified && !state.composing,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Message", color = Muted) },
                shape = RoundedCornerShape(26.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = Panel,
                    unfocusedContainerColor = Panel,
                    disabledContainerColor = Panel,
                    focusedBorderColor = Purple,
                    unfocusedBorderColor = Line,
                    focusedTextColor = TextMain,
                    unfocusedTextColor = TextMain,
                    disabledTextColor = Muted
                ),
                maxLines = 5
            )
            Spacer(Modifier.width(8.dp))
            Box(
                Modifier.size(48.dp).clip(CircleShape)
                    .background(if (state.keyVerified) Brush.linearGradient(listOf(Purple, PurpleLight)) else Brush.linearGradient(listOf(Line, Line)))
                    .clickable(enabled = state.keyVerified && !state.composing) {
                        model.sendMessage(input)
                        input = ""
                    },
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Default.Send, null, tint = Color.White) }
        }
        Text("Messages are end-to-end encrypted on your device.", color = Muted, fontSize = 10.sp, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 8.dp))
    }
    if (showFingerprint) {
        AlertDialog(
            onDismissRequest = { showFingerprint = false },
            containerColor = Panel,
            title = { Text("Encryption fingerprint", color = TextMain) },
            text = {
                Column {
                    Text("Contact: @${state.peerName ?: "contact"}", color = Muted, fontSize = 12.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(state.peerFingerprint ?: "Fingerprint unavailable", color = TextMain, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(10.dp))
                    Text(
                        "Compare every group with your contact in person or through a separate trusted channel. A fingerprint sent only through this chat is not independent verification.",
                        color = Muted, fontSize = 11.sp, lineHeight = 16.sp
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { model.verifyPeerKey(); showFingerprint = false },
                    enabled = !state.keyVerified
                ) { Text(if (state.keyVerified) "Verified" else "I compared and verified", color = PurpleLight) }
            },
            dismissButton = { TextButton(onClick = { showFingerprint = false }) { Text("Close", color = Muted) } }
        )
    }
}

@Composable
private fun MessageBubble(message: UiMessage) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (message.mine) Arrangement.End else Arrangement.Start) {
        Column(
            Modifier.widthIn(max = 310.dp).clip(
                if (message.mine) RoundedCornerShape(19.dp, 19.dp, 5.dp, 19.dp)
                else RoundedCornerShape(19.dp, 19.dp, 19.dp, 5.dp)
            )
                .background(if (message.mine) Brush.horizontalGradient(listOf(Purple, PurpleLight)) else Brush.linearGradient(listOf(PanelRaised, PanelRaised)))
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            Text(message.text, color = Color.White, fontSize = 14.sp, lineHeight = 20.sp)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End, modifier = Modifier.align(Alignment.End)) {
                Text(formatClock(message.createdAt), color = Color.White.copy(alpha = .62f), fontSize = 9.sp)
                if (message.mine) {
                    Spacer(Modifier.width(4.dp))
                    Text(
                        when (message.deliveryState) { "queued" -> "◷"; "read" -> "✓✓"; "delivered" -> "✓✓"; else -> "✓" },
                        color = Color.White.copy(alpha = .8f), fontSize = 10.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun ProfilePage(model: MainViewModel, state: CrazeUiState) {
    var editPhoto by remember { mutableStateOf(false) }
    var photoUrl by remember(state.photoUrl) { mutableStateOf(state.photoUrl.orEmpty()) }
    Scaffold(containerColor = Ink, bottomBar = { BottomTabs(AppPage.PROFILE, model) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Box(
                Modifier.fillMaxWidth().height(172.dp)
                    .background(Brush.horizontalGradient(listOf(Purple, PurpleLight)))
            ) {
                IconButton(onClick = model::openSettings, modifier = Modifier.align(Alignment.TopEnd).padding(13.dp)) {
                    Icon(Icons.Default.Tune, null, tint = Color.White)
                }
                Avatar(state.username, state.photoUrl, 112)
            }
            Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(10.dp))
                Text(state.username, color = TextMain, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
                Text("@${state.username.lowercase()}", color = Muted, fontSize = 13.sp)
                Spacer(Modifier.height(8.dp))
                Text("Private conversations. Encrypted on this device.", color = Muted, fontSize = 12.sp)
                Spacer(Modifier.height(20.dp))
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(vertical = 17.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Metric(state.chats.size.toString(), "Friends")
                    Metric("—", "Groups")
                    Metric("—", "Media")
                }
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = { editPhoto = true }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = Purple)) {
                        Icon(Icons.Default.Edit, null, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text("Edit profile")
                    }
                    val context = LocalContext.current
                    OutlinedButton(
                        onClick = {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, "Find me on CrazeChat: @${state.username}")
                            }
                            context.startActivity(Intent.createChooser(sendIntent, "Share CrazeChat profile"))
                        },
                        modifier = Modifier.weight(1f),
                        border = androidx.compose.foundation.BorderStroke(1.dp, Line)
                    ) {
                        Icon(Icons.Default.Share, null, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text("Share")
                    }
                }
                Spacer(Modifier.height(25.dp))
                SectionLabel("ACCOUNT")
                SettingsRow(Icons.Default.AlternateEmail, "Username", "@${state.username}", {})
                SettingsRow(Icons.Default.Security, "Identity", "X25519 · end-to-end encrypted", {})
                SettingsRow(Icons.Default.CalendarMonth, "Member", "CrazeChat account", {})
            }
        }
    }
    if (editPhoto) {
        AlertDialog(
            onDismissRequest = { editPhoto = false },
            containerColor = Panel,
            title = { Text("Profile photo", color = TextMain) },
            text = {
                Column {
                    Text("Add a direct HTTPS image URL. The current backend stores the URL only.", color = Muted, fontSize = 12.sp)
                    Spacer(Modifier.height(12.dp))
                    DarkField(photoUrl, { photoUrl = it }, "https://example.com/photo.jpg")
                }
            },
            confirmButton = { TextButton(onClick = { model.updateProfilePhoto(photoUrl); editPhoto = false }) { Text("Save", color = PurpleLight) } },
            dismissButton = { TextButton(onClick = { editPhoto = false }) { Text("Cancel", color = Muted) } }
        )
    }
}

@Composable
private fun Metric(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = TextMain, fontSize = 21.sp, fontWeight = FontWeight.ExtraBold)
        Text(label, color = Muted, fontSize = 11.sp)
    }
}

@Composable
private fun SettingsPage(model: MainViewModel, state: CrazeUiState) {
    var showLogout by remember { mutableStateOf(false) }
    Scaffold(containerColor = Ink, bottomBar = { BottomTabs(AppPage.SETTINGS, model) }) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            item {
                Text("Settings", color = TextMain, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(17.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(19.dp)).background(Panel).clickable { model.openProfile() }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Avatar(state.username, state.photoUrl, 50)
                    Spacer(Modifier.width(13.dp))
                    Column(Modifier.weight(1f)) {
                        Text(state.username, color = TextMain, fontWeight = FontWeight.Bold)
                        Text("@${state.username.lowercase()}", color = Muted, fontSize = 12.sp)
                    }
                    Icon(Icons.Default.ChevronRight, null, tint = Muted)
                }
            }
            item { SectionLabel("PREFERENCES") }
            item {
                SettingSwitch(Icons.Default.Notifications, "Notifications", "Generic encrypted-message alerts", state.notificationsEnabled, model::setNotificationsEnabled)
            }
            item {
                SettingsRow(Icons.Default.DarkMode, "Dark mode", "Always on in this version") { model.showInfo("The current CrazeChat design supports the dark theme only.") }
            }
            item {
                SettingsRow(Icons.Default.Language, "Language", state.language) { model.showInfo("English is the current app language.") }
            }
            item { SectionLabel("PRIVACY AND SUPPORT") }
            item { SettingsRow(Icons.Default.Shield, "Privacy and security", "Device encryption and contact verification", model::openPrivacy) }
            item { SettingsRow(Icons.Default.Storage, "Storage and data", formatBytes(state.storageBytes), model::openStorage) }
            item { SettingsRow(Icons.Default.HelpOutline, "Help center", "Account and encryption guidance") { model.showInfo("Contact CrazeStudio support for account assistance.") } }
            item {
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).clickable { showLogout = true }.padding(17.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Logout, null, tint = Color(0xFFFF8495))
                    Spacer(Modifier.width(13.dp))
                    Text("Log out", color = Color(0xFFFF8495), fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }
    if (showLogout) {
        AlertDialog(
            onDismissRequest = { showLogout = false },
            containerColor = Panel,
            title = { Text("Log out of CrazeChat?", color = TextMain) },
            text = { Text("This removes the local session and identity key from this device. Your local encrypted message archive will also be cleared.", color = Muted) },
            confirmButton = { TextButton(onClick = { showLogout = false; model.signOut() }) { Text("Log out", color = Color(0xFFFF8495)) } },
            dismissButton = { TextButton(onClick = { showLogout = false }) { Text("Cancel", color = Muted) } }
        )
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
    Column(Modifier.fillMaxSize().padding(21.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = model::openSettings) { Icon(Icons.Default.ArrowBack, null, tint = TextMain) }
            Text("Privacy and security", color = TextMain, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(12.dp))
        SecurityCard(Icons.Default.Lock, "Encrypted local vault", "Session data and cached message envelopes are protected using AES-256-GCM with a key held by Android Keystore.")
        SecurityCard(Icons.Default.Fingerprint, "Contact identity verification", "A contact's X25519 public-key fingerprint must be compared outside the chat and verified before remote messages can sync or send.")
        SecurityCard(Icons.Default.Lock, "End-to-end message encryption", "X25519 key agreement, HKDF-SHA256 and AES-256-GCM encrypt message content on the device. The backend stores encrypted envelopes.")
        SecurityCard(Icons.Default.Code, "Native security layer", "libcraze.so validates request fields and holds an XOR-obfuscated build configuration. It increases reverse-engineering effort; it cannot make an APK-embedded gateway key secret.")
        Spacer(Modifier.height(8.dp))
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
        SecurityCard(Icons.Default.WarningAmber, "Device loss", "Uninstalling the app or clearing its data removes the local vault. A separate backup/export flow is not included in this Gradle build yet.")
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
