package com.example.ui.screens

import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.asImageBitmap
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.text.selection.SelectionContainer
import com.example.R
import com.example.data.ChatEntity
import com.example.data.FirebaseUserDto
import com.example.ui.theme.*
import com.example.viewmodel.HomeViewModel
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onChatClicked: (String) -> Unit,
    onProfileClicked: () -> Unit,
    onSecurityInfoClicked: () -> Unit,
    onSettingsClicked: () -> Unit,
    onRegisterSecondUser: () -> Unit
) {
    val chats by viewModel.chats.collectAsState()
    val currentUsername by viewModel.currentUsername.collectAsState()
    val currentUserId by viewModel.currentUserId.collectAsState()
    val profiles by viewModel.profiles.collectAsState()
    val canAddProfile by viewModel.canAddProfile.collectAsState()
    val availableUsers by viewModel.availableUsers.collectAsState()
    val isLoadingUsers by viewModel.isLoadingUsers.collectAsState()
    val currentUserPfp by viewModel.currentUserPfp.collectAsState()

    var showNewChatDialog by remember { mutableStateOf(false) }
    var showNewGroupDialog by remember { mutableStateOf(false) }
    var showCreateChatChoiceSheet by remember { mutableStateOf(false) }
    var chatToDelete by remember { mutableStateOf<ChatEntity?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    var showSearchBar by remember { mutableStateOf(false) }
    var showOptionsMenu by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        viewModel.loadAvailableUsers()
    }

    Scaffold(
        topBar = {
            Column(
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.background)
                    .statusBarsPadding()
            ) {
                // Top App Bar
                TopAppBar(
                    title = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_crazechat_logo),
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(28.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "CrazeChat",
                                fontWeight = FontWeight.ExtraBold,
                                fontSize = 22.sp,
                                color = MaterialTheme.colorScheme.onBackground,
                                letterSpacing = (-0.5).sp
                            )
                        }
                    },
                    actions = {
                        // Quick Switch Profile Pill (Multi-user)
                        if (profiles.size >= 2) {
                            val otherProfile = profiles.firstOrNull { it.userId != currentUserId }
                            if (otherProfile != null) {
                                Surface(
                                    shape = RoundedCornerShape(16.dp),
                                    color = MaterialTheme.colorScheme.primaryContainer,
                                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)),
                                    modifier = Modifier
                                        .clickable { viewModel.switchProfile(otherProfile) }
                                        .padding(end = 6.dp)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                    ) {
                                        Icon(
                                            Icons.Default.SwapHoriz,
                                            contentDescription = "Switch Account",
                                            modifier = Modifier.size(14.dp),
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text(
                                            text = otherProfile.username,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.primary
                                        )
                                    }
                                }
                            }
                        }

                        // Profile Avatar Button (Displays encrypted PFP)
                        IconButton(
                            onClick = onProfileClicked,
                            modifier = Modifier.size(36.dp)
                        ) {
                            AvatarCircle(
                                name = currentUsername,
                                size = 30.dp,
                                bitmap = currentUserPfp
                            )
                        }

                        // Search Toggle Icon
                        IconButton(onClick = { showSearchBar = !showSearchBar }) {
                            Icon(
                                imageVector = if (showSearchBar) Icons.Default.Close else Icons.Default.Search,
                                contentDescription = "Search",
                                tint = MaterialTheme.colorScheme.onBackground,
                                modifier = Modifier.size(22.dp)
                            )
                        }

                        // More Menu (3 Dots)
                        Box {
                            IconButton(onClick = { showOptionsMenu = true }) {
                                Icon(
                                    Icons.Default.MoreVert,
                                    contentDescription = "Options",
                                    tint = MaterialTheme.colorScheme.onBackground,
                                    modifier = Modifier.size(22.dp)
                                )
                            }
                            DropdownMenu(
                                expanded = showOptionsMenu,
                                onDismissRequest = { showOptionsMenu = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("New Group Chat") },
                                    leadingIcon = {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_group_add),
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    },
                                    onClick = {
                                        showOptionsMenu = false
                                        showNewGroupDialog = true
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Profile") },
                                    leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                                    onClick = {
                                        showOptionsMenu = false
                                        onProfileClicked()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Settings") },
                                    leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                                    onClick = {
                                        showOptionsMenu = false
                                        onSettingsClicked()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Security Info") },
                                    leadingIcon = {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_shield_e2ee),
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    },
                                    onClick = {
                                        showOptionsMenu = false
                                        onSecurityInfoClicked()
                                    }
                                )
                                if (canAddProfile) {
                                    HorizontalDivider()
                                    DropdownMenuItem(
                                        text = { Text("Register User 2 (Slot 2/2)") },
                                        leadingIcon = { Icon(Icons.Default.Add, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                                        onClick = {
                                            showOptionsMenu = false
                                            onRegisterSecondUser()
                                        }
                                    )
                                }
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background
                    )
                )

                // Expandable Search Bar
                AnimatedVisibility(visible = showSearchBar) {
                    Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
                        OutlinedTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            placeholder = { Text("Search chats...", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp) },
                            leadingIcon = {
                                Icon(Icons.Default.Search, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                            },
                            trailingIcon = {
                                if (searchQuery.isNotEmpty()) {
                                    IconButton(onClick = { searchQuery = "" }) {
                                        Icon(Icons.Default.Close, contentDescription = "Clear", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                                    }
                                }
                            },
                            shape = RoundedCornerShape(24.dp),
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                                focusedBorderColor = MaterialTheme.colorScheme.primary,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.6f)
                            ),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(50.dp)
                        )
                    }
                }

                // Sleek, accessible User ID Banner so user always knows and can share their ID
                if (currentUserId.isNotBlank()) {
                    Surface(
                        shape = RoundedCornerShape(14.dp),
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
                        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Surface(
                                shape = CircleShape,
                                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                                modifier = Modifier.size(28.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(
                                        imageVector = Icons.Default.Key,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.width(10.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Your User ID (Share to receive chats)",
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                                    fontWeight = FontWeight.Medium
                                )
                                SelectionContainer {
                                    Text(
                                        text = currentUserId,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                            IconButton(
                                onClick = {
                                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = ClipData.newPlainText("CrazeChat User ID", currentUserId)
                                    clipboard.setPrimaryClip(clip)
                                    Toast.makeText(context, "User ID copied!", Toast.LENGTH_SHORT).show()
                                },
                                modifier = Modifier.size(34.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.ContentCopy,
                                    contentDescription = "Copy User ID",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                            IconButton(
                                onClick = {
                                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, "Here is my CrazeChat User ID: $currentUserId")
                                    }
                                    context.startActivity(Intent.createChooser(shareIntent, "Share User ID"))
                                },
                                modifier = Modifier.size(34.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Share,
                                    contentDescription = "Share User ID",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }
                }
            }
        },
        bottomBar = {
            // Balanced, Clean Navigation bar showing only Chats and Settings
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.background,
                tonalElevation = 6.dp,
                modifier = Modifier.navigationBarsPadding()
            ) {
                NavigationBarItem(
                    selected = true,
                    onClick = { /* Already on Chats */ },
                    icon = {
                        Icon(
                            imageVector = Icons.Default.ChatBubble,
                            contentDescription = "Chats"
                        )
                    },
                    label = { Text("Chats", fontSize = 12.sp, fontWeight = FontWeight.Bold) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = MaterialTheme.colorScheme.primary,
                        selectedTextColor = MaterialTheme.colorScheme.primary,
                        indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                )

                NavigationBarItem(
                    selected = false,
                    onClick = { onSettingsClicked() },
                    icon = {
                        Icon(
                            imageVector = Icons.Outlined.Settings,
                            contentDescription = "Settings"
                        )
                    },
                    label = { Text("Settings", fontSize = 12.sp) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = MaterialTheme.colorScheme.primary,
                        selectedTextColor = MaterialTheme.colorScheme.primary,
                        indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                )
            }
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showCreateChatChoiceSheet = true },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
                shape = CircleShape,
                modifier = Modifier.size(56.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = "New Chat or Group",
                    modifier = Modifier.size(28.dp)
                )
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .navigationBarsPadding()
                .background(MaterialTheme.colorScheme.background)
        ) {
            val filteredChats = if (searchQuery.isBlank()) {
                chats
            } else {
                chats.filter {
                    (if (it.isGroup) it.groupName else it.peerUsername).contains(searchQuery, ignoreCase = true)
                }
            }

            if (chats.isEmpty()) {
                EmptyChatsState(
                    onNewChat = { showCreateChatChoiceSheet = true }
                )
            } else if (filteredChats.isEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 28.dp, vertical = 64.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        imageVector = Icons.Default.SearchOff,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(36.dp)
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "No chats found",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Try another name or clear your search.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    TextButton(onClick = { searchQuery = "" }) {
                        Text("Clear search")
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 12.dp)
                ) {
                    item(key = "conversation_heading") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 18.dp, end = 18.dp, top = 12.dp, bottom = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = if (showSearchBar && searchQuery.isNotBlank()) "Search results" else "Messages",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onBackground
                            )
                            Text(
                                text = filteredChats.size.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    items(filteredChats, key = { it.chatId }) { chat ->
                        ChatItemRow(
                            chat = chat,
                            onChatClicked = { onChatClicked(chat.chatId) },
                            onLongClick = { chatToDelete = chat }
                        )
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                            modifier = Modifier.padding(start = 82.dp, end = 16.dp)
                        )
                    }
                }
            }
        }

        // Choice sheet between 1-on-1 Chat and Group Chat
        if (showCreateChatChoiceSheet) {
            ModalBottomSheet(
                onDismissRequest = { showCreateChatChoiceSheet = false },
                containerColor = MaterialTheme.colorScheme.surface
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp)
                ) {
                    Text(
                        text = "Start Conversation",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    ListItem(
                        headlineContent = { Text("New Direct Chat", fontWeight = FontWeight.SemiBold) },
                        supportingContent = { Text("Encrypted 1-on-1 private messaging", fontSize = 12.sp) },
                        leadingContent = {
                            Surface(
                                shape = CircleShape,
                                color = MaterialTheme.colorScheme.primaryContainer,
                                modifier = Modifier.size(42.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(Icons.Default.Person, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                }
                            }
                        },
                        modifier = Modifier.clickable {
                            showCreateChatChoiceSheet = false
                            showNewChatDialog = true
                        }
                    )
                    ListItem(
                        headlineContent = { Text("New Group Chat", fontWeight = FontWeight.SemiBold) },
                        supportingContent = { Text("Encrypted group chat with multiple members", fontSize = 12.sp) },
                        leadingContent = {
                            Surface(
                                shape = CircleShape,
                                color = MaterialTheme.colorScheme.primaryContainer,
                                modifier = Modifier.size(42.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(
                                        painter = painterResource(id = R.drawable.ic_group_add),
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(22.dp)
                                    )
                                }
                            }
                        },
                        modifier = Modifier.clickable {
                            showCreateChatChoiceSheet = false
                            showNewGroupDialog = true
                        }
                    )
                    Spacer(modifier = Modifier.height(18.dp))
                }
            }
        }

        // New Chat Dialog / Search
        if (showNewChatDialog) {
            NewChatDialog(
                viewModel = viewModel,
                myUserId = currentUserId,
                availableUsers = availableUsers,
                isLoading = isLoadingUsers,
                onDismiss = { showNewChatDialog = false },
                onContactSelected = { user ->
                    showNewChatDialog = false
                    scope.launch {
                        val chatId = viewModel.getOrCreateChatWithUser(user)
                        onChatClicked(chatId)
                    }
                }
            )
        }

        // New Group Chat Dialog
        if (showNewGroupDialog) {
            NewGroupChatDialog(
                existingChats = chats.filter { !it.isGroup },
                myUserId = currentUserId,
                onDismiss = { showNewGroupDialog = false },
                onCreateGroup = { groupName, memberIds ->
                    showNewGroupDialog = false
                    scope.launch {
                        val chatId = viewModel.createGroupChat(groupName, memberIds)
                        onChatClicked(chatId)
                    }
                }
            )
        }

        // Delete Chat Confirmation Dialog
        chatToDelete?.let { chat ->
            AlertDialog(
                onDismissRequest = { chatToDelete = null },
                title = { Text("Delete Conversation") },
                text = { Text("Are you sure you want to delete this chat with ${chat.peerUsername}? All local messages will be removed.") },
                confirmButton = {
                    TextButton(
                        onClick = {
                            viewModel.deleteChat(chat.chatId)
                            chatToDelete = null
                        }
                    ) {
                        Text("Delete", color = CrazeError, fontWeight = FontWeight.Bold)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { chatToDelete = null }) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatItemRow(
    chat: ChatEntity,
    onChatClicked: () -> Unit,
    onLongClick: () -> Unit
) {
    val context = LocalContext.current
    val timeFormat = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }
    val timeString = remember(chat.lastTimestamp) {
        if (chat.lastTimestamp > 0) timeFormat.format(Date(chat.lastTimestamp)) else ""
    }

    var peerPfp by remember { mutableStateOf<Bitmap?>(null) }
    val pfpManager = remember { com.example.data.ProfileImageManager.getInstance(context) }

    LaunchedEffect(chat.peerUserId) {
        peerPfp = pfpManager.getPeerPfp(chat.peerUserId)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onChatClicked,
                onLongClick = onLongClick
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (chat.isGroup) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primaryContainer,
                modifier = Modifier.size(52.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_group),
                        contentDescription = "Group",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(26.dp)
                    )
                }
            }
        } else {
            // Contact Avatar with green online dot
            AvatarCircle(name = chat.peerUsername, size = 52.dp, showOnline = true, bitmap = peerPfp)
        }

        Spacer(modifier = Modifier.width(14.dp))

        // Name & Last Message
        Column(modifier = Modifier.weight(1f)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = if (chat.isGroup) (chat.groupName.ifBlank { chat.peerUsername }) else chat.peerUsername,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                        color = MaterialTheme.colorScheme.onBackground,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    if (chat.isGroup) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = MaterialTheme.colorScheme.primaryContainer,
                            modifier = Modifier.padding(horizontal = 2.dp)
                        ) {
                            Text(
                                text = "GROUP",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.ExtraBold,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp)
                            )
                        }
                    } else {
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            painter = painterResource(id = R.drawable.ic_lock_badge),
                            contentDescription = "Encrypted",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(13.dp)
                        )
                    }
                }
                if (timeString.isNotBlank()) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = timeString,
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Double check icon indicating E2E delivered & secure
                    Icon(
                        painter = painterResource(id = R.drawable.ic_double_check),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(modifier = Modifier.width(5.dp))
                    val subtitle = if (chat.lastMessageValue.isBlank() || chat.lastMessageValue == "End-to-end encrypted chat started") {
                        "Encrypted chat started"
                    } else {
                        chat.lastMessageValue
                    }
                    Text(
                        text = subtitle,
                        fontSize = 13.sp,
                        fontWeight = if (chat.unreadCount > 0) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (chat.unreadCount > 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                if (chat.unreadCount > 0) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = chat.unreadCount.toString(),
                                color = MaterialTheme.colorScheme.onPrimary,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AvatarCircle(
    name: String,
    size: Dp = 48.dp,
    showOnline: Boolean = false,
    bitmap: Bitmap? = null
) {
    val initial = name.take(1).uppercase().ifEmpty { "U" }
    val gradientPairs = listOf(
        Pair(Color(0xFF2563EB), Color(0xFF60A5FA)),
        Pair(Color(0xFF7C3AED), Color(0xFFA78BFA)),
        Pair(Color(0xFFDB2777), Color(0xFFF472B6)),
        Pair(Color(0xFF059669), Color(0xFF34D399)),
        Pair(Color(0xFFD97706), Color(0xFFFBBF24)),
        Pair(Color(0xFF4F46E5), Color(0xFF818CF8))
    )
    val colorIndex = (name.hashCode().coerceAtLeast(0)) % gradientPairs.size
    val (startColor, endColor) = gradientPairs[colorIndex]

    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.BottomEnd
    ) {
        Surface(
            shape = CircleShape,
            modifier = Modifier.fillMaxSize()
        ) {
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = "$name Avatar",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Brush.linearGradient(listOf(startColor, endColor))),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = initial,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = (size.value * 0.42f).sp
                    )
                }
            }
        }

        if (showOnline) {
            Surface(
                shape = CircleShape,
                color = CrazeSuccess,
                border = androidx.compose.foundation.BorderStroke(2.dp, Color.White),
                modifier = Modifier.size(size * 0.28f)
            ) {}
        }
    }
}

@Composable
fun EmptyChatsState(onNewChat: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // High quality SVG Vector Illustration
        Icon(
            painter = painterResource(id = R.drawable.ic_chat_empty),
            contentDescription = "No Chats",
            tint = Color.Unspecified,
            modifier = Modifier.size(110.dp)
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = "No Conversations Yet",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onBackground
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "All messages are end-to-end encrypted and automatically erased from the cloud server upon delivery.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            lineHeight = 20.sp
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = onNewChat,
            shape = RoundedCornerShape(24.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp)
        ) {
            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("Start New Chat", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        }
    }
}

@Composable
fun NewChatDialog(
    viewModel: HomeViewModel,
    myUserId: String,
    availableUsers: List<FirebaseUserDto>,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onContactSelected: (FirebaseUserDto) -> Unit
) {
    val context = LocalContext.current
    var searchQuery by remember { mutableStateOf("") }
    val searchResult by viewModel.searchResult.collectAsState()
    val searchError by viewModel.searchError.collectAsState()
    var isSearching by remember { mutableStateOf(false) }

    // Clear search states on open/dismiss
    LaunchedEffect(Unit) {
        viewModel.searchUser("")
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Chat, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Add User by ID", fontWeight = FontWeight.ExtraBold, fontSize = 20.sp, color = MaterialTheme.colorScheme.onBackground)
            }
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                if (myUserId.isNotBlank()) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f),
                        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Your User ID (Share with friends):", fontSize = 11.sp, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f))
                                SelectionContainer {
                                    Text(myUserId, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                }
                            }
                            IconButton(
                                onClick = {
                                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = ClipData.newPlainText("CrazeChat User ID", myUserId)
                                    clipboard.setPrimaryClip(clip)
                                    Toast.makeText(context, "Your User ID copied!", Toast.LENGTH_SHORT).show()
                                },
                                modifier = Modifier.size(28.dp)
                            ) {
                                Icon(Icons.Default.ContentCopy, contentDescription = "Copy", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(15.dp))
                            }
                        }
                    }
                }

                Text(
                    text = "For maximum privacy, other users on the server are not listed. Enter the exact User ID to start a chat.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 17.sp,
                    modifier = Modifier.padding(bottom = 12.dp)
                )

                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    placeholder = { Text("Enter exact User ID...", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp) },
                    leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                    shape = RoundedCornerShape(24.dp),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline
                    ),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                Button(
                    onClick = {
                        if (searchQuery.isNotBlank()) {
                            isSearching = true
                            viewModel.searchUser(searchQuery)
                        }
                    },
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                    modifier = Modifier.fillMaxWidth().height(42.dp),
                    enabled = searchQuery.isNotBlank()
                ) {
                    Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Search User ID", fontWeight = FontWeight.Bold)
                }

                Spacer(modifier = Modifier.height(16.dp))

                if (isLoading || isSearching) {
                    // Check if search has resolved
                    LaunchedEffect(searchResult, searchError) {
                        if (searchResult != null || searchError != null) {
                            isSearching = false
                        }
                    }
                }

                if (isSearching) {
                    Box(modifier = Modifier.fillMaxWidth().height(100.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                } else if (searchResult != null) {
                    val result = searchResult!!
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f),
                        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            AvatarCircle(name = result.username, size = 44.dp, showOnline = true)
                            Spacer(modifier = Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = result.username,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 15.sp,
                                    color = MaterialTheme.colorScheme.onBackground
                                )
                                Text(
                                    text = "ID: ${result.userId.take(8)}...",
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            IconButton(
                                onClick = { onContactSelected(result) }
                            ) {
                                Icon(Icons.Default.CheckCircle, contentDescription = "Add", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(30.dp))
                            }
                        }
                    }
                } else if (searchError != null && searchQuery.isNotBlank()) {
                    Box(modifier = Modifier.fillMaxWidth().height(60.dp), contentAlignment = Alignment.Center) {
                        Text(
                            text = searchError!!,
                            color = MaterialTheme.colorScheme.error,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.SemiBold)
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
        shape = RoundedCornerShape(24.dp)
    )
}

@Composable
fun NewGroupChatDialog(
    existingChats: List<ChatEntity>,
    myUserId: String,
    onDismiss: () -> Unit,
    onCreateGroup: (groupName: String, memberIds: List<String>) -> Unit
) {
    var groupName by remember { mutableStateOf("") }
    var memberIdInput by remember { mutableStateOf("") }
    val selectedMembers = remember { mutableStateListOf<String>() }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.size(36.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_group_add),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.width(10.dp))
                Text("Create Group Chat", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            }
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 420.dp)
            ) {
                Text(
                    text = "Messages in this group are end-to-end encrypted with all participants.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = groupName,
                    onValueChange = { groupName = it },
                    label = { Text("Group Name") },
                    placeholder = { Text("e.g. Friends & Family") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "Add Members by User ID:",
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp
                )
                Spacer(modifier = Modifier.height(4.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = memberIdInput,
                        onValueChange = { memberIdInput = it.trim() },
                        placeholder = { Text("User ID (e.g. user_84f93a1c)", fontSize = 12.sp) },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Button(
                        onClick = {
                            if (memberIdInput.isNotBlank() && memberIdInput != myUserId && !selectedMembers.contains(memberIdInput)) {
                                selectedMembers.add(memberIdInput)
                                memberIdInput = ""
                            }
                        },
                        enabled = memberIdInput.isNotBlank()
                    ) {
                        Text("Add")
                    }
                }

                if (selectedMembers.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Added (${selectedMembers.size}):", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.height(4.dp))
                    LazyColumn(modifier = Modifier.heightIn(max = 90.dp)) {
                        items(selectedMembers.size) { idx ->
                            val uid = selectedMembers[idx]
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 2.dp)
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(uid, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                    IconButton(
                                        onClick = { selectedMembers.remove(uid) },
                                        modifier = Modifier.size(24.dp)
                                    ) {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_close),
                                            contentDescription = "Remove",
                                            modifier = Modifier.size(14.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if (existingChats.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(10.dp))
                    Text("Or select from contacts:", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(4.dp))
                    LazyColumn(modifier = Modifier.heightIn(max = 120.dp)) {
                        items(existingChats.size) { idx ->
                            val c = existingChats[idx]
                            val isSelected = selectedMembers.contains(c.peerUserId)
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = if (isSelected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 2.dp)
                                    .clickable {
                                        if (isSelected) {
                                            selectedMembers.remove(c.peerUserId)
                                        } else if (c.peerUserId.isNotBlank()) {
                                            selectedMembers.add(c.peerUserId)
                                        }
                                    }
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    AvatarCircle(name = c.peerUsername, size = 26.dp)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(c.peerUsername, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                                    if (isSelected) {
                                        Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (groupName.isNotBlank()) {
                        onCreateGroup(groupName, selectedMembers.toList())
                    }
                },
                enabled = groupName.isNotBlank()
            ) {
                Text("Create Group")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
        shape = RoundedCornerShape(24.dp)
    )
}
