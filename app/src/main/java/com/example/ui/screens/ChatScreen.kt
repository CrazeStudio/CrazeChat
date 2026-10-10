package com.example.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import org.json.JSONObject
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.R
import com.example.data.CryptoManager
import com.example.data.MessageEntity
import com.example.ui.theme.*
import com.example.viewmodel.ChatViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel,
    onBackClicked: () -> Unit
) {
    val messages by viewModel.messages.collectAsState()
    val pinnedMessages by viewModel.pinnedMessages.collectAsState()
    val chat by viewModel.chat.collectAsState()
    val groupInfo by viewModel.groupInfo.collectAsState()
    val privateKey by viewModel.privateKey.collectAsState()
    val currentUserId by viewModel.currentUserId.collectAsState()
    val replyTarget by viewModel.replyTargetMessage.collectAsState()

    var inputMessage by remember { mutableStateOf("") }
    var editingMessage by remember { mutableStateOf<MessageEntity?>(null) }
    var selectedMessageForAction by remember { mutableStateOf<MessageEntity?>(null) }
    var highlightedMessageId by remember { mutableStateOf<String?>(null) }
    var showGroupDetailsDialog by remember { mutableStateOf(false) }
    var showAddMemberDialog by remember { mutableStateOf(false) }
    var newMemberIdInput by remember { mutableStateOf("") }
    var showMenu by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    val messageActionSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var isMessageActionSheetClosing by remember { mutableStateOf(false) }
    val context = LocalContext.current

    // Keep the sheet composed until its hide animation finishes. Removing ModalBottomSheet
    // immediately from its onClick can interrupt its anchored-drag/animation state.
    fun dismissMessageActionSheet() {
        if (isMessageActionSheetClosing) return
        isMessageActionSheetClosing = true
        coroutineScope.launch {
            try {
                messageActionSheetState.hide()
            } finally {
                selectedMessageForAction = null
                isMessageActionSheetClosing = false
            }
        }
    }

    val isGroupChat = chat?.isGroup == true || viewModel.chatId.startsWith("group_")
    val peerPublicKey = chat?.peerPublicKey ?: ""

    // Auto-scroll on new messages
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    // Clear highlight after 1.8 seconds
    LaunchedEffect(highlightedMessageId) {
        if (highlightedMessageId != null) {
            delay(1800)
            highlightedMessageId = null
        }
    }

    // Top pinned message if available
    val activePinnedMessage = remember(pinnedMessages) {
        pinnedMessages.firstOrNull()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column(modifier = Modifier.background(MaterialTheme.colorScheme.background).statusBarsPadding()) {
                TopAppBar(
                    title = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(enabled = isGroupChat) {
                                    if (isGroupChat) showGroupDetailsDialog = true
                                }
                        ) {
                            if (isGroupChat) {
                                Surface(
                                    shape = CircleShape,
                                    color = MaterialTheme.colorScheme.primaryContainer,
                                    modifier = Modifier.size(40.dp)
                                ) {
                                    Box(contentAlignment = Alignment.Center) {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_group),
                                            contentDescription = "Group",
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(22.dp)
                                        )
                                    }
                                }
                            } else {
                                AvatarCircle(
                                    name = chat?.peerUsername ?: "User",
                                    size = 40.dp,
                                    showOnline = true
                                )
                            }

                            Spacer(modifier = Modifier.width(10.dp))

                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = if (isGroupChat) (chat?.groupName?.ifBlank { "Group Chat" } ?: "Group Chat") else (chat?.peerUsername ?: "Chat"),
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 16.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = MaterialTheme.colorScheme.onBackground
                                )
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        painter = painterResource(id = R.drawable.ic_shield_e2ee),
                                        contentDescription = null,
                                        tint = CrazeSuccess,
                                        modifier = Modifier.size(11.dp)
                                    )
                                    Spacer(modifier = Modifier.width(3.dp))
                                    Text(
                                        text = if (isGroupChat) {
                                            val count = groupInfo?.members?.size ?: (chat?.memberIdsJson?.split(",")?.filter { it.isNotBlank() }?.size ?: 2)
                                            "$count members • Encrypted"
                                        } else {
                                            "online • E2EE"
                                        },
                                        fontSize = 12.sp,
                                        color = CrazeSuccess,
                                        fontWeight = FontWeight.Medium
                                    )
                                }
                            }
                        }
                    },
                    navigationIcon = {
                        IconButton(onClick = onBackClicked) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Back",
                                tint = MaterialTheme.colorScheme.onBackground
                            )
                        }
                    },
                    actions = {
                        if (isGroupChat) {
                            IconButton(onClick = { showAddMemberDialog = true }) {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_group_add),
                                    contentDescription = "Add Member",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(22.dp)
                                )
                            }
                        }
                        Box {
                            IconButton(onClick = { showMenu = true }) {
                                Icon(
                                    imageVector = Icons.Default.MoreVert,
                                    contentDescription = "More",
                                    tint = MaterialTheme.colorScheme.onBackground
                                )
                            }
                            DropdownMenu(
                                expanded = showMenu,
                                onDismissRequest = { showMenu = false }
                            ) {
                                if (isGroupChat) {
                                    DropdownMenuItem(
                                        text = { Text("Group Details") },
                                        leadingIcon = {
                                            Icon(
                                                painter = painterResource(id = R.drawable.ic_group),
                                                contentDescription = null,
                                                modifier = Modifier.size(20.dp)
                                            )
                                        },
                                        onClick = {
                                            showMenu = false
                                            showGroupDetailsDialog = true
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Add Member") },
                                        leadingIcon = {
                                            Icon(
                                                painter = painterResource(id = R.drawable.ic_group_add),
                                                contentDescription = null,
                                                modifier = Modifier.size(20.dp)
                                            )
                                        },
                                        onClick = {
                                            showMenu = false
                                            showAddMemberDialog = true
                                        }
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("Clear Local Chat", color = MaterialTheme.colorScheme.error) },
                                    leadingIcon = {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_trash),
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.error,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    },
                                    onClick = {
                                        viewModel.clearAllChatMessages()
                                        showMenu = false
                                    }
                                )
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background
                    )
                )

                // Animated Pinned Message Bar
                AnimatedVisibility(
                    visible = activePinnedMessage != null,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    if (activePinnedMessage != null) {
                        val pinnedText = remember(activePinnedMessage.messageId) {
                            if (isGroupChat) {
                                CryptoManager.decryptGroupMessage(viewModel.chatId, activePinnedMessage.ciphertext, activePinnedMessage.nonce)
                            } else {
                                CryptoManager.decryptMessage(
                                    myPrivateKeyBase64 = privateKey,
                                    theirPublicKeyBase64 = peerPublicKey,
                                    ciphertextBase64 = activePinnedMessage.ciphertext,
                                    nonceBase64 = activePinnedMessage.nonce
                                )
                            }
                        }

                        Surface(
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            tonalElevation = 2.dp,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val index = messages.indexOfFirst { it.messageId == activePinnedMessage.messageId }
                                    if (index >= 0) {
                                        coroutineScope.launch {
                                            listState.animateScrollToItem(index)
                                            highlightedMessageId = activePinnedMessage.messageId
                                        }
                                    }
                                }
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_pin),
                                    contentDescription = "Pinned",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(modifier = Modifier.width(10.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "Pinned Message",
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                    Text(
                                        text = pinnedText.ifBlank { "Encrypted Message" },
                                        fontSize = 13.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                IconButton(
                                    onClick = { viewModel.togglePinMessage(activePinnedMessage.messageId) },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(
                                        painter = painterResource(id = R.drawable.ic_close),
                                        contentDescription = "Unpin",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.background)
                    .navigationBarsPadding()
                    .imePadding()
            ) {
                // Animated Inline Editing Bar (Shown when editing message)
                AnimatedVisibility(
                    visible = editingMessage != null,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    if (editingMessage != null) {
                        val elapsed = System.currentTimeMillis() - editingMessage!!.timestamp
                        val minutesRemaining = maxOf(0L, (10 * 60 * 1000L - elapsed) / (60 * 1000L))

                        Surface(
                            color = MaterialTheme.colorScheme.primaryContainer,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_edit),
                                    contentDescription = "Editing",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "Editing message",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                    Text(
                                        text = "$minutesRemaining min remaining to edit",
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer
                                    )
                                }
                                IconButton(
                                    onClick = {
                                        editingMessage = null
                                        inputMessage = ""
                                    },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(
                                        painter = painterResource(id = R.drawable.ic_close),
                                        contentDescription = "Cancel edit",
                                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                // Reply Preview Bar
                if (replyTarget != null) {
                    val target = replyTarget!!
                    val replyPreviewText = remember(target.messageId) {
                        if (isGroupChat) {
                            CryptoManager.decryptGroupMessage(viewModel.chatId, target.ciphertext, target.nonce)
                        } else {
                            CryptoManager.decryptMessage(
                                myPrivateKeyBase64 = privateKey,
                                theirPublicKeyBase64 = peerPublicKey,
                                ciphertextBase64 = target.ciphertext,
                                nonceBase64 = target.nonce
                            )
                        }
                    }
                    
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                modifier = Modifier
                                    .width(4.dp)
                                    .height(32.dp)
                                    .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = if (target.senderId == currentUserId) "Replying to yourself" else "Replying to ${target.senderUsername}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(
                                    text = replyPreviewText.ifBlank { "Encrypted Message" },
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            IconButton(onClick = { viewModel.clearReplyTarget() }) {
                                Icon(Icons.Default.Close, contentDescription = "Cancel Reply", modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }

                // Sleek Modern Input Bar (WhatsApp Style, Auto-Expanding, Safe Area Insets)
                Surface(
                    color = Color.Transparent,
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.Bottom
                    ) {
                        Surface(
                            shape = RoundedCornerShape(24.dp),
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            tonalElevation = 1.dp,
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 48.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 4.dp),
                                contentAlignment = Alignment.CenterStart
                            ) {
                                OutlinedTextField(
                                    value = inputMessage,
                                    onValueChange = { inputMessage = it },
                                    placeholder = {
                                        Text(
                                            text = if (editingMessage != null) "Edit message..." else "Message",
                                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                                            fontSize = 16.sp
                                        )
                                    },
                                    singleLine = false,
                                    maxLines = 6,
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedContainerColor = Color.Transparent,
                                        unfocusedContainerColor = Color.Transparent,
                                        focusedBorderColor = Color.Transparent,
                                        unfocusedBorderColor = Color.Transparent,
                                        focusedTextColor = MaterialTheme.colorScheme.onBackground,
                                        unfocusedTextColor = MaterialTheme.colorScheme.onBackground,
                                        cursorColor = MaterialTheme.colorScheme.primary
                                    ),
                                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                                        fontSize = 16.sp
                                    ),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 4.dp)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.width(6.dp))

                        // Keep the send control steady and easy to tap.
                        FloatingActionButton(
                            onClick = {
                                if (inputMessage.isNotBlank()) {
                                    val toEdit = editingMessage
                                    if (toEdit != null) {
                                        viewModel.editMessage(toEdit.messageId, inputMessage) { success, errorMsg ->
                                            if (success) {
                                                Toast.makeText(context, "Message edited", Toast.LENGTH_SHORT).show()
                                                editingMessage = null
                                                inputMessage = ""
                                            } else {
                                                Toast.makeText(context, errorMsg ?: "Edit failed", Toast.LENGTH_SHORT).show()
                                            }
                                        }
                                    } else {
                                        val rt = replyTarget
                                        val rtPreview = if (rt != null) {
                                            if (isGroupChat) {
                                                CryptoManager.decryptGroupMessage(viewModel.chatId, rt.ciphertext, rt.nonce)
                                            } else {
                                                CryptoManager.decryptMessage(
                                                    myPrivateKeyBase64 = privateKey,
                                                    theirPublicKeyBase64 = peerPublicKey,
                                                    ciphertextBase64 = rt.ciphertext,
                                                    nonceBase64 = rt.nonce
                                                )
                                            }
                                        } else ""
                                        viewModel.sendMessage(inputMessage, rtPreview)
                                        inputMessage = ""
                                    }
                                }
                            },
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            shape = CircleShape,
                            modifier = Modifier.size(48.dp),
                            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 2.dp)
                        ) {
                            if (editingMessage != null) {
                                Icon(
                                    imageVector = Icons.Default.Check,
                                    contentDescription = "Save edit",
                                    tint = Color.White,
                                    modifier = Modifier.size(22.dp)
                                )
                            } else {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_send_plane),
                                    contentDescription = "Send",
                                    tint = Color.White,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    Spacer(modifier = Modifier.height(8.dp))

                    // E2EE Privacy Notice Banner
                    Box(
                        modifier = Modifier.fillMaxWidth(),
                        contentAlignment = Alignment.Center
                    ) {
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.7f),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
                            modifier = Modifier.fillMaxWidth(0.95f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_shield_e2ee),
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = if (isGroupChat) {
                                        "Encrypted Group Chat: All messages are authenticated and private to members."
                                    } else {
                                        "End-to-End Encrypted: Cloud copies are permanently deleted immediately after delivery."
                                    },
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                    lineHeight = 15.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                }

                itemsIndexed(messages, key = { _, it -> it.messageId }) { _, message ->
                    val isMe = message.senderId == currentUserId
                    val isHighlighted = highlightedMessageId == message.messageId

                    MessageBubbleItem(
                        message = message,
                        isMe = isMe,
                        isGroup = isGroupChat,
                        isHighlighted = isHighlighted,
                        privateKey = privateKey,
                        peerPublicKey = peerPublicKey,
                        chatId = viewModel.chatId,
                        onLongClick = { selectedMessageForAction = message },
                        onRetry = { viewModel.retryMessage(message.messageId) }
                    )
                }

                item { Spacer(modifier = Modifier.height(14.dp)) }
            }
        }
    }

    // Message Actions Bottom Sheet (Pin, Edit, Copy, Delete)
    if (selectedMessageForAction != null) {
        val selected = selectedMessageForAction!!
        val isMe = selected.senderId == currentUserId
        val elapsed = System.currentTimeMillis() - selected.timestamp
        val isWithin10Min = elapsed <= 10 * 60 * 1000L
        val minutesRemaining = maxOf(0L, (10 * 60 * 1000L - elapsed) / (60 * 1000L))

        val decryptedText = remember(selected.messageId) {
            if (isGroupChat) {
                CryptoManager.decryptGroupMessage(viewModel.chatId, selected.ciphertext, selected.nonce)
            } else {
                CryptoManager.decryptMessage(
                    myPrivateKeyBase64 = privateKey,
                    theirPublicKeyBase64 = peerPublicKey,
                    ciphertextBase64 = selected.ciphertext,
                    nonceBase64 = selected.nonce
                )
            }
        }

        ModalBottomSheet(
            sheetState = messageActionSheetState,
            onDismissRequest = {
                selectedMessageForAction = null
                isMessageActionSheetClosing = false
            },
            containerColor = MaterialTheme.colorScheme.surface,
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
            ) {
                Text(
                    text = "Message Options",
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = decryptedText.take(60).ifBlank { "Encrypted text" },
                    fontSize = 13.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(20.dp))

                // Quick Reactions Row
                val commonReactions = listOf("❤️", "😂", "😮", "😢", "😡", "👍")
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    commonReactions.forEach { emoji ->
                        val iconRes = when (emoji) {
                            "❤️" -> R.drawable.ic_reaction_heart
                            "😂" -> R.drawable.ic_reaction_laugh
                            "😮" -> R.drawable.ic_reaction_wow
                            "😢" -> R.drawable.ic_reaction_sad
                            "😡" -> R.drawable.ic_reaction_angry
                            "👍" -> R.drawable.ic_reaction_like
                            else -> R.drawable.ic_reaction_like
                        }
                        Surface(
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                            modifier = Modifier
                                .size(44.dp)
                                .clickable(enabled = !isMessageActionSheetClosing) {
                                    viewModel.sendReaction(selected.messageId, emoji)
                                    dismissMessageActionSheet()
                                }
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    painter = painterResource(id = iconRes),
                                    contentDescription = emoji,
                                    tint = Color.Unspecified,
                                    modifier = Modifier.size(24.dp)
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // 0. Reply
                ListItem(
                    headlineContent = { Text("Reply") },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Reply,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(24.dp)
                        )
                    },
                    modifier = Modifier.clickable(enabled = !isMessageActionSheetClosing) {
                        viewModel.setReplyTarget(selected)
                        dismissMessageActionSheet()
                    }
                )

                // 1. Pin / Unpin
                ListItem(
                    headlineContent = { Text(if (selected.isPinned) "Unpin Message" else "Pin Message") },
                    leadingContent = {
                        Icon(
                            painter = painterResource(id = if (selected.isPinned) R.drawable.ic_unpin else R.drawable.ic_pin),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp)
                        )
                    },
                    modifier = Modifier.clickable(enabled = !isMessageActionSheetClosing) {
                        viewModel.togglePinMessage(selected.messageId)
                        dismissMessageActionSheet()
                    }
                )

                // 2. Edit (Allowed within 10 minutes for author)
                if (isMe) {
                    ListItem(
                        headlineContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("Edit Message")
                                Spacer(modifier = Modifier.width(6.dp))
                                if (isWithin10Min) {
                                    Surface(
                                        shape = RoundedCornerShape(10.dp),
                                        color = MaterialTheme.colorScheme.primaryContainer,
                                        modifier = Modifier.padding(horizontal = 4.dp)
                                    ) {
                                        Text(
                                            text = "$minutesRemaining min left",
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                } else {
                                    Surface(
                                        shape = RoundedCornerShape(10.dp),
                                        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.6f),
                                        modifier = Modifier.padding(horizontal = 4.dp)
                                    ) {
                                        Text(
                                            text = "Expired (>10m)",
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.error,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                }
                            }
                        },
                        leadingContent = {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_edit),
                                contentDescription = null,
                                tint = if (isWithin10Min) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                                modifier = Modifier.size(22.dp)
                            )
                        },
                        modifier = Modifier.clickable(enabled = isWithin10Min && !isMessageActionSheetClosing) {
                            editingMessage = selected
                            inputMessage = decryptedText
                            dismissMessageActionSheet()
                        }
                    )
                }

                // 3. Copy Text
                ListItem(
                    headlineContent = { Text("Copy Text") },
                    leadingContent = {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_copy),
                            contentDescription = null,
                            modifier = Modifier.size(22.dp)
                        )
                    },
                    modifier = Modifier.clickable(enabled = !isMessageActionSheetClosing) {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("CrazeChat", decryptedText))
                        Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                        dismissMessageActionSheet()
                    }
                )

                // 4. Delete for Everyone (if isMe)
                if (isMe) {
                    ListItem(
                        headlineContent = { Text("Delete for Everyone", color = MaterialTheme.colorScheme.error) },
                        leadingContent = {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_trash),
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(22.dp)
                            )
                        },
                        modifier = Modifier.clickable(enabled = !isMessageActionSheetClosing) {
                            viewModel.deleteMessage(selected.messageId, forEveryone = true)
                            dismissMessageActionSheet()
                            Toast.makeText(context, "Message deleted for everyone", Toast.LENGTH_SHORT).show()
                        }
                    )
                }

                // 5. Delete for Me
                ListItem(
                    headlineContent = { Text("Delete for Me", color = MaterialTheme.colorScheme.error) },
                    leadingContent = {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_trash),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(22.dp)
                        )
                    },
                    modifier = Modifier.clickable(enabled = !isMessageActionSheetClosing) {
                        viewModel.deleteMessage(selected.messageId, forEveryone = false)
                        dismissMessageActionSheet()
                    }
                )

                Spacer(modifier = Modifier.height(18.dp))
            }
        }
    }

    // Group Details Dialog
    if (showGroupDetailsDialog && isGroupChat) {
        val membersList = remember(groupInfo, chat) {
            val list = mutableListOf<String>()
            groupInfo?.members?.keys?.let { list.addAll(it) }
            if (list.isEmpty() && !chat?.memberIdsJson.isNullOrBlank()) {
                list.addAll(chat!!.memberIdsJson.split(",").filter { it.isNotBlank() })
            }
            list.distinct()
        }

        AlertDialog(
            onDismissRequest = { showGroupDetailsDialog = false },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_group),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = chat?.groupName ?: "Group Details", fontWeight = FontWeight.Bold)
                }
            },
            text = {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "Group ID: ${viewModel.chatId}",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Members (${membersList.size}):",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp
                    )
                    Spacer(modifier = Modifier.height(6.dp))

                    LazyColumn(modifier = Modifier.heightIn(max = 240.dp)) {
                        items(membersList.size) { idx ->
                            val uid = membersList[idx]
                            val isOwner = uid == (groupInfo?.groupOwnerId ?: chat?.groupOwnerId)
                            val isMeUid = uid == currentUserId

                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 3.dp)
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    AvatarCircle(name = uid.take(2), size = 28.dp)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = if (isMeUid) "$uid (You)" else uid,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Medium,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        if (isOwner) {
                                            Text(
                                                text = "Group Admin",
                                                fontSize = 10.sp,
                                                color = MaterialTheme.colorScheme.primary,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                    IconButton(
                                        onClick = {
                                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                            clipboard.setPrimaryClip(ClipData.newPlainText("User ID", uid))
                                            Toast.makeText(context, "Copied ID", Toast.LENGTH_SHORT).show()
                                        },
                                        modifier = Modifier.size(24.dp)
                                    ) {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_copy),
                                            contentDescription = "Copy ID",
                                            modifier = Modifier.size(14.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showGroupDetailsDialog = false }) {
                    Text("Close")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showGroupDetailsDialog = false
                        showAddMemberDialog = true
                    }
                ) {
                    Text("Add Member")
                }
            }
        )
    }

    // Add Member to Group Dialog
    if (showAddMemberDialog && isGroupChat) {
        AlertDialog(
            onDismissRequest = {
                showAddMemberDialog = false
                newMemberIdInput = ""
            },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_group_add),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = "Add Member to Group", fontWeight = FontWeight.Bold)
                }
            },
            text = {
                Column {
                    Text(
                        text = "Enter the exact User ID of the person you want to add to this group:",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedTextField(
                        value = newMemberIdInput,
                        onValueChange = { newMemberIdInput = it.trim() },
                        placeholder = { Text("e.g. user_84f93a1c") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (newMemberIdInput.isNotBlank()) {
                            viewModel.addMemberToGroup(newMemberIdInput) { success, msg ->
                                Toast.makeText(context, msg ?: if (success) "Added" else "Failed", Toast.LENGTH_SHORT).show()
                                if (success) {
                                    showAddMemberDialog = false
                                    newMemberIdInput = ""
                                }
                            }
                        }
                    }
                ) {
                    Text("Add")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showAddMemberDialog = false
                        newMemberIdInput = ""
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MessageBubbleItem(
    message: MessageEntity,
    isMe: Boolean,
    isGroup: Boolean,
    isHighlighted: Boolean,
    privateKey: String,
    peerPublicKey: String,
    chatId: String,
    onLongClick: () -> Unit,
    onRetry: () -> Unit
) {
    val decryptedText = remember(message.messageId, message.ciphertext, privateKey, peerPublicKey) {
        if (isGroup) {
            CryptoManager.decryptGroupMessage(chatId, message.ciphertext, message.nonce)
        } else {
            if (message.ciphertext.isBlank() || privateKey.isBlank() || peerPublicKey.isBlank()) {
                message.plaintext.ifBlank { "Encrypted Message" }
            } else {
                CryptoManager.decryptMessage(
                    myPrivateKeyBase64 = privateKey,
                    theirPublicKeyBase64 = peerPublicKey,
                    ciphertextBase64 = message.ciphertext,
                    nonceBase64 = message.nonce
                )
            }
        }
    }

    val bubbleShape = if (isMe) {
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 18.dp, bottomEnd = 4.dp)
    } else {
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 4.dp, bottomEnd = 18.dp)
    }

    // Smooth flash animation if highlighted via pinned bar tap
    val animatedBgColor by animateColorAsState(
        targetValue = if (isHighlighted) {
            MaterialTheme.colorScheme.tertiaryContainer
        } else if (isMe) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        },
        animationSpec = tween(durationMillis = 350),
        label = "bubbleBg"
    )

    val textColor = if (isMe && !isHighlighted) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant
    val timeFormat = remember { SimpleDateFormat("h:mm a", Locale.getDefault()) }
    val timeString = remember(message.timestamp) { timeFormat.format(Date(message.timestamp)) }

    // Distinct sender name color for group chats
    val senderColor = remember(message.senderId) {
        val colors = listOf(
            Color(0xFF2563EB), Color(0xFF0D9488), Color(0xFF7C3AED),
            Color(0xFFEA580C), Color(0xFFD97706), Color(0xFF0284C7)
        )
        colors[Math.floorMod(message.senderId.hashCode(), colors.size)]
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (isMe) Alignment.End else Alignment.Start
    ) {
        Surface(
            shape = bubbleShape,
            color = animatedBgColor,
            tonalElevation = if (isMe) 0.dp else 1.dp,
            shadowElevation = 1.dp,
            border = if (!isMe && !isHighlighted) BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)) else null,
            modifier = Modifier
                .widthIn(min = 90.dp, max = 295.dp)
                .combinedClickable(
                    onClick = { /* Tap */ },
                    onLongClick = onLongClick
                )
        ) {
            Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp)) {
                // Sender name in group chat
                if (isGroup && !isMe && message.senderUsername.isNotBlank()) {
                    Text(
                        text = message.senderUsername,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = senderColor,
                        modifier = Modifier.padding(bottom = 2.dp)
                    )
                }

                // Reply Preview inside bubble
                if (message.replyToId.isNotBlank()) {
                    Surface(
                        shape = RoundedCornerShape(8.dp),
                        color = (if (isMe && !isHighlighted) Color.White else MaterialTheme.colorScheme.primary).copy(alpha = 0.15f),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp)
                    ) {
                        Row(modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
                            Box(
                                modifier = Modifier
                                    .width(3.dp)
                                    .height(24.dp)
                                    .background(if (isMe && !isHighlighted) Color.White else MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text(
                                    text = message.replyToSender.ifBlank { "User" },
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (isMe && !isHighlighted) Color.White else MaterialTheme.colorScheme.primary
                                )
                                Text(
                                    text = message.replyToText.ifBlank { "Encrypted Message" },
                                    fontSize = 11.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = textColor.copy(alpha = 0.8f)
                                )
                            }
                        }
                    }
                }

                Text(
                    text = decryptedText.ifBlank { "Encrypted Message" },
                    color = textColor,
                    fontSize = 15.sp,
                    lineHeight = 20.sp
                )

                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    modifier = Modifier.align(Alignment.End),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Pinned icon indicator
                    if (message.isPinned) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_pin),
                            contentDescription = "Pinned",
                            tint = if (isMe && !isHighlighted) Color.White.copy(alpha = 0.85f) else MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .size(12.dp)
                                .padding(end = 2.dp)
                        )
                    }

                    // Edited chip indicator
                    if (message.isEdited) {
                        Text(
                            text = "(edited)",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (isMe && !isHighlighted) Color.White.copy(alpha = 0.7f) else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                            modifier = Modifier.padding(end = 4.dp)
                        )
                    }

                    Text(
                        text = timeString,
                        fontSize = 11.sp,
                        color = if (isMe && !isHighlighted) Color.White.copy(alpha = 0.75f) else MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    if (isMe) {
                        Spacer(modifier = Modifier.width(4.dp))
                        when (message.status) {
                            "SENDING" -> {
                                Icon(
                                    imageVector = Icons.Default.Schedule,
                                    contentDescription = "Sending",
                                    modifier = Modifier.size(12.dp),
                                    tint = Color.White.copy(alpha = 0.75f)
                                )
                            }
                            "SENT" -> {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_single_check),
                                    contentDescription = "Sent",
                                    modifier = Modifier.size(13.dp),
                                    tint = Color.White.copy(alpha = 0.85f)
                                )
                            }
                            "FAILED" -> {
                                Icon(
                                    imageVector = Icons.Default.ErrorOutline,
                                    contentDescription = "Failed to send. Tap to retry",
                                    modifier = Modifier
                                        .size(14.dp)
                                        .clickable(onClick = onRetry),
                                    tint = Color(0xFFFF8A80)
                                )
                            }
                            "SERVER_DELETED" -> {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_server_deleted),
                                    contentDescription = "Cloud Purged",
                                    modifier = Modifier.size(14.dp),
                                    tint = Color(0xFF6EE7B7)
                                )
                            }
                            else -> {
                                Icon(
                                    painter = painterResource(id = R.drawable.ic_double_check),
                                    contentDescription = "Delivered",
                                    modifier = Modifier.size(14.dp),
                                    tint = Color.White
                                )
                            }
                        }
                    }
                }
            }
        }

        // Reactions floating slightly below the bubble
        if (message.reactionsJson.isNotBlank()) {
            val reactions = remember(message.reactionsJson) {
                try {
                    val json = JSONObject(message.reactionsJson)
                    val list = mutableListOf<String>()
                    val keys = json.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        list.add(json.getString(key))
                    }
                    list.distinct()
                } catch (e: Exception) { emptyList<String>() }
            }
            
            if (reactions.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .padding(top = (-10).dp, start = if (isMe) 0.dp else 12.dp, end = if (isMe) 12.dp else 0.dp)
                        .background(MaterialTheme.colorScheme.surface, CircleShape)
                        .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f), CircleShape)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    reactions.forEach { emoji ->
                        val iconRes = when (emoji) {
                            "❤️" -> R.drawable.ic_reaction_heart
                            "😂" -> R.drawable.ic_reaction_laugh
                            "😮" -> R.drawable.ic_reaction_wow
                            "😢" -> R.drawable.ic_reaction_sad
                            "😡" -> R.drawable.ic_reaction_angry
                            "👍" -> R.drawable.ic_reaction_like
                            else -> R.drawable.ic_reaction_like
                        }
                        Icon(
                            painter = painterResource(id = iconRes),
                            contentDescription = emoji,
                            tint = Color.Unspecified,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        }
    }
}
