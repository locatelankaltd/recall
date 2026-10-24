import 'package:flutter/widgets.dart';

String tr(BuildContext context, String key) =>
    strings[Localizations.localeOf(context).languageCode]?[key] ??
    strings['en']?[key] ??
    key;

String trParams(BuildContext context, String key, Map<String, String> values) {
  var translated = tr(context, key);
  for (final entry in values.entries) {
    translated = translated.replaceAll('{${entry.key}}', entry.value);
  }
  return translated;
}

/// Captured content and interface language are intentionally independent.
/// The interface supports English, Spanish and French. Service-provided errors,
/// user content and fictional example content can retain their original language.
const strings = <String, Map<String, String>>{
  'en': {
    'today': 'Today',
    'projects': 'Projects',
    'sources': 'Sources',
    'addUpdate': 'Add update',
    'welcome': 'A clear plan.\nEven when it changes.',
    'welcomeBody':
        'Keep the current plan, changing requests and next steps together. Start with what you choose to share.',
    'start': 'Create your first project',
    'tryExample': 'Explore the example',
    'sample': 'Example workspace',
    'sampleNote': 'Fictional projects. Responses here are simulations.',
    'overview': 'A little clarity for what comes next.',
    'review': 'Needs your review',
    'waiting': 'Waiting for someone',
    'dueNext': 'Due next',
    'allClear': 'Room to focus.',
    'noReview': 'No changes need your review.',
    'currentPlan': 'Current plan',
    'proposed': 'Proposed change',
    'confirmed': 'Confirmed',
    'privatePlan': 'Your saved plan',
    'version': 'Version',
    'newProject': 'New project',
    'projectTitle': 'Project name',
    'clientName': 'Who are you working with?',
    'category': 'Kind of work',
    'create': 'Create project',
    'cancel': 'Cancel',
    'save': 'Save',
    'searchProjects': 'Find a project',
    'emptyProjects': 'Your next project starts here.',
    'emptyProjectsBody':
        'Give it a name, then add the plan you want to keep clear.',
    'emptySources': 'Every change has a starting point.',
    'emptySourcesBody':
        'Sources attached to your changes appear here, in their original language.',
    'addItem': 'Add a plan item',
    'itemTitle': 'Deliverable or commitment',
    'details': 'Details and conditions',
    'owner': 'Responsible person',
    'you': 'You',
    'date': 'Delivery date',
    'noDate': 'No date agreed',
    'totalFee': 'Total fee',
    'amount': 'Amount',
    'currency': 'Currency',
    'noAmount': 'No amount recorded',
    'baselineNote':
        'This is your private working plan. Saving it does not confirm agreement by another person.',
    'source': 'Source',
    'original': 'Original text',
    'recollection': 'Your recollection',
    'sourceLanguage': 'Source language',
    'sourceHint':
        'Paste the message or describe what you remember. Keep conditions and uncertainty.',
    'newValues': 'Review the proposed values',
    'current': 'Current',
    'new': 'Proposed',
    'reviewSource': 'Inspect source',
    'keepChange': 'Save proposed change',
    'reviewNote':
        'A request stays proposed until the required people confirm the same version.',
    'acceptMine': 'Accept this version as me',
    'clientPreview': 'Preview client review',
    'history': 'History',
    'correct': 'Request a correction',
    'correction': 'Correction requested',
    'correctionNote': 'What needs to change?',
    'sendCorrection': 'Save correction request',
    'sourceEvidence': 'Source and context',
    'noSources': 'No source attached.',
    'pending': 'Awaiting response',
    'myAnswer': 'Your answer is needed',
    'inspect': 'Review changes',
    'sampleConfirm': 'Simulate client confirmation',
    'simulation':
        'Example only. This does not send a message or verify a person.',
    'realSharing':
        'A preview is not a sent request. Real responses require a connected review service.',
    'export': 'Export your workspace',
    'import': 'Restore an export',
    'settings': 'Your workspace',
    'language': 'Interface language',
    'privacy': 'Privacy and storage',
    "privacyBody":
        "Mobile project text uses device secure storage. Audio attachments are ordinary app-private files and are not encrypted by that service. Web storage has different protections. Account projects use the configured cloud service; device projects are never uploaded automatically. Optional AI sends only the specific text or whole recording you explicitly approve.",
    'appearance': 'Appearance follows your device',
    'delete': 'Delete local workspace',
    'deleteConfirm': 'Delete your local workspace?',
    'deleteBody':
        'Export anything you need first. This cannot be undone. This action does not delete a remote account.',
    'deleteAction': 'Delete local data',
    'savedLocal': 'Saved on this device',
    'noCloud': 'Local workspace · no cloud sync',
    'markProgress': 'Delivery progress',
    'open': 'Not started',
    'inProgress': 'In progress',
    'delivered': 'Delivered',
    'accepted': 'Accepted by you',
    'deliveryNote':
        'Delivery progress is separate from the plan. A file sent does not imply client acceptance or payment.',
    'newPlan': 'A place for the plan.',
    'newPlanBody':
        'Add what is already known. Review changing requests against it later.',
    'file': 'Import text',
    'paste': 'Paste text',
    'record': 'Record a debrief',
    'stop': 'Stop recording',
    "recordNotice":
        "Record your own recollection, or a meeting after appropriate notice and consent. Recording does not upload audio. Transcription is a separate action that asks for your permission.",
    "recorded":
        "Audio saved on this device. Add a written source, or separately choose transcription when available.",
    'required': 'Add a value to continue.',
    'invalidAmount':
        'Use a non-negative amount, with at most two decimal places.',
    'sourceRequired': 'Add the source or your recollection.',
    'chooseProject': 'Choose a project',
    'chooseItem': 'Which plan item changed?',
    'noItems': 'Add a plan item before reviewing an update.',
    'resetDemo': 'Leave the example',
    'loading': 'Opening your workspace…',
    'retry': 'Try again',
    'error': 'Your work needs attention',
    'exportNote':
        'This export contains private project and source text. Recording files are not included; export recordings separately before moving devices. Share only with people you choose.',
    'support': 'Build information',
    "supportBody":
        "Recall 0.2. Sign in for your cloud workspace and review links. Optional AI and store subscriptions are available when their services are configured. Optional deadline reminders are available on Android and iOS with notification permission.",
    'sourceSaved': 'Original language preserved',
    'reviewEmpty': 'No pending changes. The current plan is up to date.',
    'copy': 'Copy export',
    'copied': 'Copied to clipboard',
    'projectCount': 'Active projects',
    'needAnswer': 'Awaiting answers',
    'exportRecording': 'Export recording',
    'recordingExportFailed': 'The recording could not be exported. Try again.',
    'recordingUnavailable':
        'This recording is unavailable. It may have been moved or restored on another device. Open the original device to export it.',
    'viewAll': 'See all',
    'close': 'Close',
    "sourceTooLong":
        "Keep this source within 30,000 characters. Your existing text has not been replaced.",
    "emptyClipboard": "There is no text on the clipboard.",
    "clipboardError":
        "Clipboard access was not available. You can type the source below.",
    "fileTooLarge": "Choose a text file smaller than 1 MB.",
    "fileUnreadable":
        "This file could not be read. Your existing source is unchanged.",
    "fileEmpty": "This file does not contain text.",
    "fileEncoding":
        "Choose a UTF-8 text file. Nothing in your source has been replaced.",
    "fileImportFailed":
        "The file could not be imported. Your source is still here.",
    "beginRecording": "Start recording",
    "micDenied":
        "Microphone access was not granted. You can write your recollection instead.",
    "oneRecording":
        "Remove or download the current recording before making another.",
    "audioRemoveFailed": "The recording could not be removed. Try again.",
    "recordUnsupported":
        "Recording is not supported by this browser or device. You can still add text.",
    "recordFailed":
        "Recording could not start. Your written source has been kept.",
    "audioUnavailable":
        "No recording was returned. Your written source is unchanged.",
    "webAudioSession":
        "Recording available in this browser session only. Download it before leaving.",
    "stopFailed":
        "The recording could not be saved. Your written source is unchanged.",
    "downloadAudio": "Save a copy of the recording",
    "audioCopySaved": "Recording copy saved.",
    "audioSaveFailed":
        "The recording copy could not be saved. The current recording is unchanged.",
    "unsupportedCurrency":
        "This item uses a currency this editor does not yet support. Its amount and currency have been kept unchanged.",
    "reviewValuesFirst": "Review the values and select the confirmation below.",
    "noChangedValues":
        "Change at least one plan value before saving a proposal.",
    "proposalSaved": "Proposal saved. The current plan has not changed.",
    "saveFailed": "Could not save. Your source and edits are still here.",
    "back": "Back",
    "manualReview":
        "Add the source, then review the new plan values. Optional AI actions run only after you choose them.",
    "recordingNow": "Recording",
    "removeAudio": "Remove recording",
    "importedFile": "Imported",
    "clearDate": "Remove the proposed date",
    "totalAmountNote":
        "Total for this item, not an additional fee. No thousands separators.",
    "reviewedValues": "I reviewed the source, values and conditions.",
    "sharedTextTitle": "Text shared with Recall",
    "sharedTextBody":
        "Choose a project to review this text. Nothing is saved or sent until you save the proposed change.",
    "sharedTextReview": "Review shared text",
    "sharedTextDiscard": "Discard shared text",
    "sharedTextTooLarge":
        "This shared text exceeds the 1 MiB receiving limit. Share a smaller selection.",
    "sharedTextUnsupported":
        "Recall receives plain text and links shared as text. Attached files and content URIs are not supported here.",
    "sharedTextEmpty": "This share did not contain any text.",
    "sharedTextInvalid":
        "This share could not be read. Try sharing plain text again.",
    "sharedTextQueueFull":
        "Some incoming shares could not be kept. Review or discard the waiting text, then share those messages again.",
    "sharePlatformNote":
        "Receiving shared text is available on Android. An iOS share extension is not included in this build.",
    "interfaceLanguageNote":
        "Choose English, Spanish or French for the interface. Original sources keep their own language. Some service errors and example content may appear in English.",
    "openSourceLicenses": "Open-source licenses",
    "workspaceExportTitle": "Recall workspace export",
    "exportTooLarge": "Choose an export smaller than 1 MB.",
    "restoreWarning":
        "Restoring replaces the local workspace. Export your current work first.",
    "planComparisonLabel":
        "Two versions of a plan, with a clear change between them",
    "accountTitle": "Your account",
    "accountDeleteTitle": "Delete your account?",
    "accountDeleteBody":
        "This permanently deletes your account, cloud projects, and review links. Your separate device workspace stays on this device. Deleting your account does not cancel App Store or Google Play subscriptions; manage or cancel them in the store.",
    "accountCurrentPassword": "Current password",
    "accountKeep": "Keep account",
    "accountDeletePermanently": "Delete permanently",
    "accountNewPasswordHeading": "Choose a new password.",
    "accountSharedHeading": "A shared place for your plans.",
    "accountWelcomeHeading": "Keep the next version together.",
    "accountSignedInBody":
        "Your account workspace stores cloud projects and supports real review links. Device projects remain separate.",
    "accountSignInBody":
        "Sign in to create cloud projects and invite people to review a specific change. Your device projects are never uploaded automatically.",
    "accountUnavailable": "Cloud accounts are unavailable",
    "accountNotConfigured":
        "This build does not have a cloud service configured. You can continue using the device workspace.",
    "accountEmailVerified": "Email verified",
    "accountEmailUnverified": "Email verification needed",
    "accountCheckInbox": "Check your inbox before using cloud projects.",
    "accountResendVerification": "Resend verification email",
    "accountVerifiedAction": "I verified my email",
    "accountOpenWorkspace": "Open account workspace",
    "accountSendReset": "Send a password reset email",
    "accountSignOut": "Sign out",
    "accountEmail": "Email address",
    "accountInvalidEmail": "Enter a valid email address.",
    "accountNewPassword": "New password",
    "accountPassword": "Password",
    "accountHidePassword": "Hide password",
    "accountShowPassword": "Show password",
    "accountPasswordRequired": "Enter your password.",
    "accountPasswordLength": "Use at least 8 characters.",
    "accountUpdatePassword": "Update password",
    "accountCreate": "Create account",
    "accountSignIn": "Sign in",
    "accountHaveAccount": "Already have an account? Sign in",
    "accountCreatePrompt": "New to Recall? Create an account",
    "accountForgotPassword": "Forgot password? Send reset email",
    "accountDeleteAction": "Delete account and cloud data",
    "accountVerificationPending": "Verification pending for {email}",
    "accountUseDevice": "Use device workspace",
    "publicReviewLoadFailed":
        "This review could not be opened. Check your connection or ask for a new link.",
    "publicReviewCorrectionRequired":
        "Describe what needs correcting before you send.",
    "publicReviewResponseFailed":
        "Your response could not be confirmed. Retry the same response to check safely.",
    "publicReviewTitle": "Recall · Review a change",
    "publicReviewLoading": "Opening this exact review…",
    "publicReviewUnavailable": "This review is unavailable.",
    "publicReviewUnavailableBody":
        "The link may have expired or been revoked. Ask the project owner for a new review link.",
    "publicReviewFor": "A review for {name}",
    "publicReviewIdentityNote":
        "Anyone with this private link can respond. Recall records a link-holder response; it does not verify the person’s identity. Share this link only with the intended reviewer.",
    "publicReviewChanges": "The proposed changes",
    "publicReviewCompare":
        "Compare the current plan with the proposed version below.",
    "publicReviewNoChanges":
        "There are no visible item changes in this review.",
    "publicReviewSourceHeading": "Source included with this proposal",
    "publicReviewNoSource": "No source text is included in this link.",
    "publicReviewOriginal": "Pasted original text · {language}",
    "publicReviewRecollection": "Personal recollection · {language}",
    "publicReviewOriginalNote":
        "Provided by the project owner. Recall has not authenticated the original conversation.",
    "publicReviewRecollectionNote":
        "This is someone’s recollection, not a verified quote.",
    "publicReviewSourceOmitted":
        "Some source text is outside the scope of this link and has been omitted.",
    "publicReviewStale": "This proposal is out of date.",
    "publicReviewClosed": "This review is closed.",
    "publicReviewClosedBody":
        "No response can be added here. Ask the project owner for a link to the latest proposal.",
    "publicReviewResponse": "Your response",
    "publicReviewResponseNote":
        "Confirmation applies to the exact proposed version. Requesting a correction or declining keeps this proposal from becoming the current plan.",
    "publicReviewNote": "A note or correction",
    "publicReviewNoteHint": "Required when requesting a correction",
    "publicReviewAcknowledgement":
        "I reviewed the changes and understand my response is recorded as a link holder.",
    "publicReviewConfirm": "Confirm this version",
    "publicReviewDecline": "Decline this proposal",
    "publicReviewRefresh": "Refresh review status",
    "publicReviewConfirmed": "Confirmation recorded.",
    "publicReviewCorrectionRecorded": "Correction request recorded.",
    "publicReviewDeclined": "Decline recorded.",
    "publicReviewAlreadyAnswered": "A response is already recorded.",
    "publicReviewReceiptNote":
        "This link has already received a response. The project owner can see the link-holder receipt.",
    "publicReviewReceipt": "Receipt: {receipt}",
    "publicReviewProposedVersion": "Proposed version",
    "publicReviewNoItem": "No item in this version",
    "publicReviewDue": "Due {date}",
    "publicReviewOwner": "Owner: {name}",
    "publicReviewProjectOwner": "Project owner",
    "publicReviewReviewer": "Reviewer",
    "Your session could not be refreshed. Sign in again.":
        "Your session could not be refreshed. Sign in again.",
    "Cloud accounts are not configured in this build.":
        "Cloud accounts are not configured in this build.",
    "This account request could not be completed. Check your connection and try again.":
        "This account request could not be completed. Check your connection and try again.",
    "Your account is ready.": "Your account is ready.",
    "Check your email for the verification link, then return here and sign in. If the address is already registered, use sign in or reset your password.":
        "Check your email for the verification link, then return here and sign in. If the address is already registered, use sign in or reset your password.",
    "Enter your email address first.": "Enter your email address first.",
    "If this email has an account, a password reset link will arrive shortly. Open it on this device.":
        "If this email has an account, a password reset link will arrive shortly. Open it on this device.",
    "Enter your account email first.": "Enter your account email first.",
    "If verification is needed, a new link will arrive by email.":
        "If verification is needed, a new link will arrive by email.",
    "Use a password with at least 8 characters.":
        "Use a password with at least 8 characters.",
    "Your password has been updated.": "Your password has been updated.",
    "Enter your current password to delete this account.":
        "Enter your current password to delete this account.",
    "The account changed. Sign in again before deleting.":
        "The account changed. Sign in again before deleting.",
    "Your account and cloud projects have been deleted.":
        "Your account and cloud projects have been deleted.",
    "The cloud service URL is invalid.": "The cloud service URL is invalid.",
    "The cloud service requires a secure connection.":
        "The cloud service requires a secure connection.",
    "A public client key is required.": "A public client key is required.",
    "The public client key is invalid.": "The public client key is invalid.",
    "Cloud sign in could not start. Check this build’s cloud settings and secure storage access.":
        "Cloud sign in could not start. Check this build’s cloud settings and secure storage access.",
    "This plan changed or this review is already closed. Refresh to review the latest version.":
        "This plan changed or this review is already closed. Refresh to review the latest version.",
    "This project or review link is unavailable, expired, or revoked.":
        "This project or review link is unavailable, expired, or revoked.",
    "Sign in again to continue.": "Sign in again to continue.",
    "This change could not be accepted. Review the fields and try again.":
        "This change could not be accepted. Review the fields and try again.",
    "This request was already recorded. Refresh to see the result.":
        "This request was already recorded. Refresh to see the result.",
    "The cloud request could not be completed. Try again.":
        "The cloud request could not be completed. Try again.",
    "Verify your email before signing in. Check your inbox for the verification link.":
        "Verify your email before signing in. Check your inbox for the verification link.",
    "The email or password is incorrect.":
        "The email or password is incorrect.",
    "Choose a stronger password and try again.":
        "Choose a stronger password and try again.",
    "Please wait before requesting another email.":
        "Please wait before requesting another email.",
    "This email may already have an account. Try signing in.":
        "This email may already have an account. Try signing in.",
    "This account request could not be completed. Try again.":
        "This account request could not be completed. Try again.",
    "The cloud service could not be reached. Check your connection and try again.":
        "The cloud service could not be reached. Check your connection and try again.",
    "Your account could not be deleted. Please try again.":
        "Your account could not be deleted. Please try again.",
    "Review link copied.": "Review link copied.",
    "Share a review link": "Share a review link",
    "Anyone with a link can respond. The receipt records a link holder, not a verified person. Copying or sharing a link does not mean it was delivered.":
        "Anyone with a link can respond. The receipt records a link holder, not a verified person. Copying or sharing a link does not mean it was delivered.",
    "This proposal is closed, out of date, or an example. A new link cannot be created.":
        "This proposal is closed, out of date, or an example. A new link cannot be created.",
    "A public web address is needed before links can be shared from this build.":
        "A public web address is needed before links can be shared from this build.",
    "Items this reviewer can see": "Items this reviewer can see",
    "Source text is included when every changed item is selected. Partial reviews omit source text outside their scope.":
        "Source text is included when every changed item is selected. Partial reviews omit source text outside their scope.",
    "Link expires after": "Link expires after",
    "1 hour": "1 hour",
    "1 day": "1 day",
    "7 days": "7 days",
    "Create private review link": "Create private review link",
    "Expires": "Expires",
    "Copy link": "Copy link",
    "Share link": "Share link",
    "Links for this version": "Links for this version",
    "No review links yet.": "No review links yet.",
    "Revoked": "Revoked",
    "Expired": "Expired",
    "Response recorded": "Response recorded",
    "Awaiting response": "Awaiting response",
    "Revoke": "Revoke",
    "Refresh links": "Refresh links",
    "The local recording index is full. Export recordings before adding more.":
        "The local recording index is full. Export recordings before adding more.",
    "The local recording index could not be accessed on this device.":
        "The local recording index could not be accessed on this device.",
    "The local recording index could not be saved on this device.":
        "The local recording index could not be saved on this device.",
    "The local recording index could not be cleared on this device.":
        "The local recording index could not be cleared on this device.",
    "subscription": "Subscription",
    "subscriptionBody":
        "Your free workspace remains available. Store plans appear here when configured.",
    "subscriptionFreeLimits":
        "Free: 3 projects and up to 5 AI requests per day.",
    "subscriptionProLimits":
        "Pro: 100 projects and up to 20 AI requests per day.",
    "subscriptionAllowanceNote":
        "AI features require provider availability and share a daily service budget.",
    "subscriptionLimitReached": "Your current plan limit has been reached.",
    "remindersTitle": "Deadline reminders",
    "remindersIntro":
        "Optional reminders for the workspace you are viewing. Turning them on asks your device for notification permission.",
    "remindersToggle": "Remind me about upcoming deadlines",
    "remindersTiming":
        "Recall plans up to 32 reminders for unfinished current-plan items, around 9:00 in your device time zone on the day before a deadline, or on its due date when that morning is still ahead. Dates do not imply an agreed delivery time.",
    "remindersPrivacy":
        "Notifications use generic text. Project names, people, source text and prices are never included.",
    "remindersDelivery":
        "Delivery depends on your device notification settings and battery restrictions. These are local reminders, not server push notifications.",
    "remindersScheduleCount": "Scheduled on this device: {count}",
    "remindersZone": "Device time zone: {zone}",
    "remindersLastSync": "Last checked: {date}",
    "remindersRefresh": "Refresh reminders",
    "remindersSettings": "Open notification settings",
    "remindersOff": "Reminders are off.",
    "remindersUnavailable":
        "Local deadline reminders are available on Android and iOS.",
    "remindersPermission":
        "Notification permission is blocked. Enable notifications in your device settings, then return here.",
    "remindersZoneFailed":
        "The device time zone could not be resolved. No reminders are scheduled.",
    "remindersReady": "Reminders are up to date for this workspace.",
    "remindersEmpty": "No upcoming deadlines need a reminder.",
    "remindersFailed":
        "Reminders could not be updated. Open Recall to try again.",
    "remindersSyncing": "Updating local reminders…",
    "remindersNoWorkspace": "Open a workspace to prepare its reminders.",
    "deadlineNotificationTitle": "Recall",
    "deadlineNotificationBody":
        "A project deadline is coming up. Open Recall to review your plan.",
    "subscriptionActive": "Pro verified",
    "subscriptionInactive": "Free workspace",
    "subscriptionUnverified": "Subscription not verified",
    "subscriptionUnavailable":
        "Store subscriptions are unavailable on this device or are not configured.",
    "subscriptionSignIn": "Sign in to view your subscription.",
    "subscriptionRestore": "Restore purchases",
    "subscriptionRefresh": "Verify subscription",
    "subscriptionManage": "Manage in store",
    "subscriptionCancelled": "Purchase cancelled. No subscription was changed.",
    "subscriptionPending":
        "Your purchase is pending store approval. Verify again after approval.",
    "subscriptionVerifyFailed":
        "Your purchase may be complete, but server verification is unavailable. Restore or verify again before retrying a purchase.",
    "subscriptionError":
        "The store could not complete this request. Please try again.",
    "subscriptionNoPlans": "No store plans are available right now.",
    "subscriptionBuy": "Continue with this plan",
    "subscriptionRenewal":
        "Subscriptions renew automatically unless cancelled in your store settings. The store shows the billing period, trial terms and full price before purchase.",
    "subscriptionAccountChanged":
        "Your account changed. Reopen this page for the signed-in account.",
    "subscriptionStoreBusy": "Another purchase action is still in progress.",
    "subscriptionStale": "Subscription verification needs refreshing.",
    "subscriptionTerms": "Review store terms before confirming payment.",
    "licenses": "Open-source licenses",
    "deleteProject": "Delete project",
    "deleteProjectBody":
        "Delete this project and its review links? Export anything you need first. Recordings on this device will also be removed when available.",
    "shareReview": "Share a review link",
    "cloudWorkspaceNote":
        "Cloud workspace. Written sources and plans are saved to your account. Recordings stay on this device.",
    "Some local recordings could not be removed. Try again.":
        "Some local recordings could not be removed. Try again.",
    "subscriptionPeriodDays": "Billing period (days): {count}",
    "subscriptionPeriodWeeks": "Billing period (weeks): {count}",
    "subscriptionPeriodMonths": "Billing period (months): {count}",
    "subscriptionPeriodYears": "Billing period (years): {count}",
    "categoryCreative": "Creative",
    "categoryServices": "Services",
    "categorySoftware": "Software",
    "categoryConsulting": "Consulting",
    "categoryEvents": "Events",
    "categoryOther": "Other",
    "cloudReviewIdentity":
        "Responses were recorded through private review links. Link possession does not verify the respondent’s identity.",
    "aiAnalyzeAction": "Get AI draft suggestions",
    "aiTranscribeAction": "Transcribe this recording",
    "aiAccountOnly":
        "Optional AI actions require a signed-in account workspace and a configured service. Manual review is always available.",
    "aiAnalyzeConsentTitle": "Send this source for AI analysis?",
    "aiAnalyzeConsentBody":
        "Send the written source below and the selected current plan item to OpenAI through your account service. This may include private client information. OpenAI processes it under its API data policies. Suggestions are drafts; no plan values are changed or saved.",
    "aiSelectedCurrentItem": "Selected current plan item",
    "aiSendText": "Send this text",
    "aiTranscribeConsentTitle": "Send the whole recording for transcription?",
    "aiTranscribeConsentBody":
        "Send this whole recording to OpenAI through your account service. It may include voices and private information. Confirm that you have permission to share it. OpenAI processes it under its API data policies. You will review and edit the transcript before choosing whether to add it. Audio is not uploaded automatically.",
    "aiSendAudio": "Send this recording",
    "aiTranscriptReviewTitle": "Review the machine transcript",
    "aiTranscriptReviewNote":
        "This machine transcript may mishear words, names, amounts or dates. Check and correct it before adding it. It is stored as your recollection, not as an authenticated original quote.",
    "aiAppendTranscript": "Add reviewed transcript",
    "aiTranscriptAdded":
        "A reviewed machine transcript was added to your written source. The recording remains on this device.",
    "aiDraftTitle": "Draft suggestions for your review",
    "aiDraftNote":
        "Nothing has been applied. Compare the source and current plan, then edit the proposed values below yourself. Check every amount, currency, date and condition before confirming your review.",
    "aiNoSuggestions":
        "No draft suggestions were returned. Continue with manual review.",
    "aiSuggestedText": "Suggested text to check",
    "aiSourceQuote": "Supporting source quote",
    "aiQuestion": "Clarification needed",
    "aiIntentRequest": "Possible change request",
    "aiIntentTentative": "Tentative idea",
    "aiIntentWithdrawal": "Possible withdrawal",
    "aiIntentNoChange": "No change identified",
    "aiIntentUnclear": "Meaning is unclear",
    "aiWorking": "Working on your request… Your plan is unchanged.",
    "aiSignIn": "Sign in to your account workspace before using AI.",
    "aiAccountChanged":
        "Your account changed. Nothing was added. Reopen this project for the signed-in account.",
    "aiConsentRequired":
        "Approve this specific AI action before sending any content.",
    "aiSourceLimit":
        "AI analysis needs a nonempty source of at most 12,000 characters and 32 KB of UTF-8 text. Your existing source is unchanged.",
    "aiItemLimit":
        "This plan item is too long or is unavailable for AI analysis. Continue with manual review.",
    "aiAudioLimit":
        "Choose a nonempty recording no larger than 20 MiB. Your written source is unchanged.",
    "aiAudioFormat":
        "This recording format is unavailable for transcription. Add a written source instead.",
    "aiInvalidResult":
        "The AI response could not be safely checked. Your source and plan are unchanged.",
    "aiAllowance":
        "The daily AI allowance or shared service budget has been reached. Continue manually or try tomorrow.",
    "aiUnavailable":
        "The AI service is not configured, is unavailable, or has reached a spending limit. Continue manually.",
    "aiTimeout":
        "The AI request timed out. No automatic retry was made. Your source and plan are unchanged.",
    "aiFailed":
        "The AI request could not complete. Your source and edits are still here. No automatic retry was made.",
    "Draft suggestions require human review. Every amount, currency and date must be checked.":
        "Draft suggestions require human review. Every amount, currency and date must be checked.",
    "Verbatim evidence does not prove the intended meaning, speaker identity or agreement.":
        "Verbatim evidence does not prove the intended meaning, speaker identity or agreement.",
    "Unsupported source evidence was discarded.":
        "Unsupported source evidence was discarded.",
    "A value without verbatim supporting evidence was discarded.":
        "A value without verbatim supporting evidence was discarded.",
  },
  'es': {
    'today': 'Hoy',
    'projects': 'Proyectos',
    'sources': 'Fuentes',
    'addUpdate': 'Añadir actualización',
    'welcome': 'Un plan claro.\nAunque las cosas cambien.',
    'welcomeBody':
        'Reúne el plan actual, las solicitudes de cambio y los próximos pasos. Tú eliges qué compartir.',
    'start': 'Crear tu primer proyecto',
    'tryExample': 'Explorar el ejemplo',
    'sample': 'Espacio de ejemplo',
    'sampleNote': 'Proyectos ficticios. Las respuestas son simulaciones.',
    'overview': 'Un poco de claridad para lo que viene.',
    'review': 'Necesita tu revisión',
    'waiting': 'Esperando respuesta',
    'dueNext': 'Próximas entregas',
    'allClear': 'Espacio para concentrarte.',
    'currentPlan': 'Plan actual',
    'proposed': 'Cambio propuesto',
    'confirmed': 'Confirmado',
    'privatePlan': 'Tu plan guardado',
    'version': 'Versión',
    'newProject': 'Nuevo proyecto',
    'projectTitle': 'Nombre del proyecto',
    'clientName': '¿Con quién trabajas?',
    'category': 'Tipo de trabajo',
    'create': 'Crear proyecto',
    'cancel': 'Cancelar',
    'save': 'Guardar',
    'searchProjects': 'Buscar un proyecto',
    'emptyProjects': 'Tu próximo proyecto empieza aquí.',
    'emptyProjectsBody': 'Dale un nombre y añade tu plan.',
    'emptySources': 'Cada cambio tiene un punto de partida.',
    'emptySourcesBody': 'Aquí aparecen las fuentes, en su idioma original.',
    'addItem': 'Añadir elemento al plan',
    'itemTitle': 'Entregable o compromiso',
    'details': 'Detalles y condiciones',
    'owner': 'Responsable',
    'you': 'Tú',
    'date': 'Fecha de entrega',
    'noDate': 'Sin fecha acordada',
    'totalFee': 'Precio total',
    'amount': 'Importe',
    'currency': 'Moneda',
    'source': 'Fuente',
    'original': 'Texto original',
    'recollection': 'Tu recuerdo',
    'sourceLanguage': 'Idioma de la fuente',
    'sourceHint': 'Pega el mensaje o describe lo que recuerdas.',
    'newValues': 'Revisa los valores propuestos',
    'current': 'Actual',
    'new': 'Propuesto',
    'reviewSource': 'Ver fuente',
    'keepChange': 'Guardar cambio propuesto',
    'acceptMine': 'Aceptar esta versión como yo',
    'clientPreview': 'Vista del cliente',
    'history': 'Historial',
    'correct': 'Solicitar corrección',
    'correction': 'Corrección solicitada',
    'correctionNote': '¿Qué debe cambiar?',
    'sendCorrection': 'Guardar solicitud',
    'pending': 'Esperando respuesta',
    'myAnswer': 'Necesitamos tu respuesta',
    'inspect': 'Revisar cambios',
    'sampleConfirm': 'Simular confirmación del cliente',
    'simulation': 'Solo un ejemplo. No envía mensajes ni verifica identidades.',
    'settings': 'Tu espacio',
    'language': 'Idioma de la interfaz',
    'privacy': 'Privacidad y almacenamiento',
    'appearance': 'Apariencia según tu dispositivo',
    'delete': 'Eliminar espacio local',
    'deleteAction': 'Eliminar datos locales',
    'savedLocal': 'Guardado en este dispositivo',
    'noCloud': 'Espacio local · sin sincronización',
    'markProgress': 'Progreso de entrega',
    'open': 'Sin empezar',
    'inProgress': 'En curso',
    'delivered': 'Entregado',
    'accepted': 'Aceptado por ti',
    'newPlan': 'Un lugar para el plan.',
    'file': 'Importar texto',
    'paste': 'Pegar texto',
    'record': 'Grabar un resumen',
    'stop': 'Detener grabación',
    'required': 'Añade un valor para continuar.',
    'sourceRequired': 'Añade la fuente o tu recuerdo.',
    'chooseProject': 'Elige un proyecto',
    'chooseItem': '¿Qué elemento cambió?',
    'noItems': 'Añade primero un elemento al plan.',
    'resetDemo': 'Salir del ejemplo',
    'loading': 'Abriendo tu espacio…',
    'retry': 'Reintentar',
    'error': 'Tu trabajo necesita atención',
    'export': 'Exportar tu espacio',
    'import': 'Restaurar exportación',
    'sourceSaved': 'Idioma original conservado',
    'copy': 'Copiar exportación',
    'support': 'Información de la versión',
    'projectCount': 'Proyectos activos',
    'needAnswer': 'Respuestas pendientes',
    'exportRecording': 'Exportar grabación',
    'recordingExportFailed':
        'No se pudo exportar la grabación. Inténtalo de nuevo.',
    'recordingUnavailable':
        'Esta grabación no está disponible. Es posible que se haya movido o restaurado en otro dispositivo. Expórtala desde el dispositivo original.',
    'viewAll': 'Ver todos',
    'close': 'Cerrar',
    "privacyBody":
        "El texto de los proyectos móviles usa el almacenamiento seguro del dispositivo. Los audios son archivos privados de la aplicación y ese servicio no los cifra. El almacenamiento web tiene otras protecciones. Los proyectos de cuenta usan el servicio en la nube configurado; los proyectos del dispositivo nunca se suben automáticamente. La IA opcional solo envía el texto concreto o la grabación completa que apruebes explícitamente.",
    "supportBody":
        "Recall 0.2. Inicia sesión para usar tu espacio en la nube y los enlaces de revisión. La IA opcional y las suscripciones de la tienda están disponibles cuando sus servicios están configurados. Los recordatorios opcionales de fechas límite están disponibles en Android e iOS con permiso de notificaciones.",
    "noReview": "No hay cambios que necesiten tu revisión.",
    "noAmount": "Sin importe registrado",
    "baselineNote":
        "Este es tu plan de trabajo privado. Guardarlo no confirma el acuerdo de otra persona.",
    "reviewNote":
        "Una solicitud sigue siendo una propuesta hasta que las personas necesarias confirmen la misma versión.",
    "sourceEvidence": "Fuente y contexto",
    "noSources": "Sin fuente adjunta.",
    "realSharing":
        "La vista previa no envía una solicitud. Las respuestas reales requieren un servicio de revisión conectado.",
    "deleteConfirm": "¿Eliminar tu espacio local?",
    "deleteBody":
        "Primero exporta lo que necesites. Esta acción es irreversible y no elimina una cuenta remota.",
    "deliveryNote":
        "El progreso de entrega es independiente del plan. Enviar un archivo no implica aceptación del cliente ni pago.",
    "newPlanBody":
        "Añade lo que ya sabes. Después compara las solicitudes de cambio con este plan.",
    "recordNotice":
        "Graba tu propio recuerdo o una reunión tras informar y obtener el consentimiento correspondiente. Grabar no sube el audio. La transcripción es una acción independiente que te pide permiso.",
    "recorded":
        "Audio guardado en este dispositivo. Añade una fuente escrita o elige la transcripción por separado si está disponible.",
    "invalidAmount":
        "Usa un importe igual o superior a cero, con un máximo de dos decimales.",
    "exportNote":
        "Esta exportación contiene texto privado de proyectos y fuentes. No incluye grabaciones; expórtalas por separado antes de cambiar de dispositivo. Compártela solo con las personas que elijas.",
    "reviewEmpty": "No hay cambios pendientes. El plan actual está al día.",
    "copied": "Copiado al portapapeles",
    "sourceTooLong":
        "Limita esta fuente a 30.000 caracteres. No se ha reemplazado tu texto actual.",
    "emptyClipboard": "No hay texto en el portapapeles.",
    "clipboardError":
        "No se pudo acceder al portapapeles. Puedes escribir la fuente abajo.",
    "fileTooLarge": "Elige un archivo de texto de menos de 1 MB.",
    "fileUnreadable":
        "No se pudo leer este archivo. Tu fuente actual sigue igual.",
    "fileEmpty": "Este archivo no contiene texto.",
    "fileEncoding":
        "Elige un archivo de texto UTF-8. No se ha reemplazado nada de tu fuente.",
    "fileImportFailed": "No se pudo importar el archivo. Tu fuente sigue aquí.",
    "beginRecording": "Iniciar grabación",
    "micDenied":
        "No se concedió acceso al micrófono. Puedes escribir tu recuerdo.",
    "oneRecording":
        "Elimina o descarga la grabación actual antes de hacer otra.",
    "audioRemoveFailed":
        "No se pudo eliminar la grabación. Inténtalo de nuevo.",
    "recordUnsupported":
        "Este navegador o dispositivo no permite grabar. Puedes añadir texto.",
    "recordFailed":
        "No se pudo iniciar la grabación. Se ha conservado tu fuente escrita.",
    "audioUnavailable":
        "No se obtuvo ninguna grabación. Tu fuente escrita sigue igual.",
    "webAudioSession":
        "La grabación solo está disponible en esta sesión del navegador. Descárgala antes de salir.",
    "stopFailed":
        "No se pudo guardar la grabación. Tu fuente escrita sigue igual.",
    "downloadAudio": "Guardar una copia de la grabación",
    "audioCopySaved": "Copia de la grabación guardada.",
    "audioSaveFailed":
        "No se pudo guardar la copia. La grabación actual sigue igual.",
    "unsupportedCurrency":
        "Este elemento usa una moneda que el editor aún no admite. Su importe y moneda se han conservado.",
    "reviewValuesFirst": "Revisa los valores y marca la confirmación de abajo.",
    "noChangedValues":
        "Cambia al menos un valor del plan antes de guardar una propuesta.",
    "proposalSaved": "Propuesta guardada. El plan actual no ha cambiado.",
    "saveFailed": "No se pudo guardar. Tu fuente y tus cambios siguen aquí.",
    "back": "Volver",
    "manualReview":
        "Añade la fuente y revisa los nuevos valores del plan. Las acciones opcionales de IA solo se ejecutan cuando las eliges.",
    "recordingNow": "Grabando",
    "removeAudio": "Eliminar grabación",
    "importedFile": "Importado",
    "clearDate": "Eliminar la fecha propuesta",
    "totalAmountNote":
        "Total de este elemento, no un cargo adicional. Sin separadores de miles.",
    "reviewedValues": "He revisado la fuente, los valores y las condiciones.",
    "sharedTextTitle": "Texto compartido con Recall",
    "sharedTextBody":
        "Elige un proyecto para revisar este texto. No se guarda ni se envía nada hasta que guardes el cambio propuesto.",
    "sharedTextReview": "Revisar texto compartido",
    "sharedTextDiscard": "Descartar texto compartido",
    "sharedTextTooLarge":
        "Este texto supera el límite de recepción de 1 MiB. Comparte una selección más pequeña.",
    "sharedTextUnsupported":
        "Recall recibe texto sin formato y enlaces compartidos como texto. Aquí no se admiten archivos adjuntos ni URI de contenido.",
    "sharedTextEmpty": "El contenido compartido no contiene texto.",
    "sharedTextInvalid":
        "No se pudo leer el contenido compartido. Intenta compartir texto sin formato de nuevo.",
    "sharedTextQueueFull":
        "No se pudo conservar parte del contenido compartido. Revisa o descarta el texto pendiente y vuelve a compartir esos mensajes.",
    "sharePlatformNote":
        "La recepción de texto compartido está disponible en Android. Esta versión no incluye una extensión para compartir en iOS.",
    "interfaceLanguageNote":
        "Elige inglés, español o francés para la interfaz. Las fuentes conservan su idioma original. Algunos errores del servicio y contenidos de ejemplo pueden aparecer en inglés.",
    "openSourceLicenses": "Licencias de código abierto",
    "workspaceExportTitle": "Exportación del espacio de Recall",
    "exportTooLarge": "Elige una exportación de menos de 1 MB.",
    "restoreWarning":
        "Restaurar reemplaza el espacio local. Exporta primero tu trabajo actual.",
    "planComparisonLabel":
        "Dos versiones de un plan con un cambio claro entre ellas",
    "accountTitle": "Tu cuenta",
    "accountDeleteTitle": "¿Eliminar tu cuenta?",
    "accountDeleteBody":
        "Esta acción elimina permanentemente tu cuenta, tus proyectos en la nube y tus enlaces de revisión. Tu espacio independiente del dispositivo permanece en este dispositivo. Eliminar tu cuenta no cancela las suscripciones de App Store o Google Play; gestiónalas o cancélalas en la tienda.",
    "accountCurrentPassword": "Contraseña actual",
    "accountKeep": "Conservar cuenta",
    "accountDeletePermanently": "Eliminar permanentemente",
    "accountNewPasswordHeading": "Elige una nueva contraseña.",
    "accountSharedHeading": "Un espacio compartido para tus planes.",
    "accountWelcomeHeading": "Mantén la próxima versión en un solo lugar.",
    "accountSignedInBody":
        "Tu espacio de cuenta guarda proyectos en la nube y permite usar enlaces reales de revisión. Los proyectos del dispositivo permanecen separados.",
    "accountSignInBody":
        "Inicia sesión para crear proyectos en la nube e invitar a otras personas a revisar un cambio concreto. Los proyectos de tu dispositivo nunca se suben automáticamente.",
    "accountUnavailable": "Las cuentas en la nube no están disponibles",
    "accountNotConfigured":
        "Esta versión no tiene un servicio en la nube configurado. Puedes seguir usando el espacio del dispositivo.",
    "accountEmailVerified": "Correo verificado",
    "accountEmailUnverified": "Debes verificar tu correo",
    "accountCheckInbox":
        "Revisa tu bandeja de entrada antes de usar proyectos en la nube.",
    "accountResendVerification": "Reenviar correo de verificación",
    "accountVerifiedAction": "He verificado mi correo",
    "accountOpenWorkspace": "Abrir espacio de la cuenta",
    "accountSendReset": "Enviar correo para restablecer contraseña",
    "accountSignOut": "Cerrar sesión",
    "accountEmail": "Dirección de correo",
    "accountInvalidEmail": "Introduce una dirección de correo válida.",
    "accountNewPassword": "Nueva contraseña",
    "accountPassword": "Contraseña",
    "accountHidePassword": "Ocultar contraseña",
    "accountShowPassword": "Mostrar contraseña",
    "accountPasswordRequired": "Introduce tu contraseña.",
    "accountPasswordLength": "Usa al menos 8 caracteres.",
    "accountUpdatePassword": "Actualizar contraseña",
    "accountCreate": "Crear cuenta",
    "accountSignIn": "Iniciar sesión",
    "accountHaveAccount": "¿Ya tienes cuenta? Inicia sesión",
    "accountCreatePrompt": "¿Es tu primera vez en Recall? Crea una cuenta",
    "accountForgotPassword":
        "¿Olvidaste la contraseña? Enviar correo de restablecimiento",
    "accountDeleteAction": "Eliminar cuenta y datos en la nube",
    "accountVerificationPending": "Verificación pendiente para {email}",
    "accountUseDevice": "Usar espacio del dispositivo",
    "publicReviewLoadFailed":
        "No se pudo abrir esta revisión. Comprueba tu conexión o solicita un nuevo enlace.",
    "publicReviewCorrectionRequired":
        "Describe qué debe corregirse antes de enviar.",
    "publicReviewResponseFailed":
        "No se pudo confirmar tu respuesta. Vuelve a intentar la misma respuesta para comprobarlo con seguridad.",
    "publicReviewTitle": "Recall · Revisar un cambio",
    "publicReviewLoading": "Abriendo esta revisión concreta…",
    "publicReviewUnavailable": "Esta revisión no está disponible.",
    "publicReviewUnavailableBody":
        "Es posible que el enlace haya caducado o se haya revocado. Pide un nuevo enlace de revisión al responsable del proyecto.",
    "publicReviewFor": "Una revisión para {name}",
    "publicReviewIdentityNote":
        "Cualquier persona con este enlace privado puede responder. Recall registra la respuesta de quien tiene el enlace; no verifica su identidad. Comparte el enlace solo con la persona que deba revisar.",
    "publicReviewChanges": "Los cambios propuestos",
    "publicReviewCompare":
        "Compara el plan actual con la versión propuesta abajo.",
    "publicReviewNoChanges":
        "No hay cambios visibles en los elementos de esta revisión.",
    "publicReviewSourceHeading": "Fuente incluida en esta propuesta",
    "publicReviewNoSource": "Este enlace no incluye texto de la fuente.",
    "publicReviewOriginal": "Texto original pegado · {language}",
    "publicReviewRecollection": "Recuerdo personal · {language}",
    "publicReviewOriginalNote":
        "Proporcionado por el responsable del proyecto. Recall no ha autenticado la conversación original.",
    "publicReviewRecollectionNote":
        "Este es el recuerdo de una persona, no una cita verificada.",
    "publicReviewSourceOmitted":
        "Se ha omitido parte del texto fuente porque queda fuera del alcance de este enlace.",
    "publicReviewStale": "Esta propuesta ya no está actualizada.",
    "publicReviewClosed": "Esta revisión está cerrada.",
    "publicReviewClosedBody":
        "Aquí no se pueden añadir respuestas. Pide al responsable del proyecto un enlace a la propuesta más reciente.",
    "publicReviewResponse": "Tu respuesta",
    "publicReviewResponseNote":
        "La confirmación se aplica a esta versión propuesta exacta. Solicitar una corrección o rechazarla impide que esta propuesta pase a ser el plan actual.",
    "publicReviewNote": "Una nota o corrección",
    "publicReviewNoteHint": "Obligatorio al solicitar una corrección",
    "publicReviewAcknowledgement":
        "He revisado los cambios y entiendo que mi respuesta se registra como la de una persona que tiene el enlace.",
    "publicReviewConfirm": "Confirmar esta versión",
    "publicReviewDecline": "Rechazar esta propuesta",
    "publicReviewRefresh": "Actualizar estado de revisión",
    "publicReviewConfirmed": "Confirmación registrada.",
    "publicReviewCorrectionRecorded": "Solicitud de corrección registrada.",
    "publicReviewDeclined": "Rechazo registrado.",
    "publicReviewAlreadyAnswered": "Ya hay una respuesta registrada.",
    "publicReviewReceiptNote":
        "Este enlace ya ha recibido una respuesta. El responsable del proyecto puede ver el comprobante de la persona que tiene el enlace.",
    "publicReviewReceipt": "Comprobante: {receipt}",
    "publicReviewProposedVersion": "Versión propuesta",
    "publicReviewNoItem": "No hay elemento en esta versión",
    "publicReviewDue": "Entrega: {date}",
    "publicReviewOwner": "Responsable: {name}",
    "publicReviewProjectOwner": "Responsable del proyecto",
    "publicReviewReviewer": "Persona revisora",
    "Your session could not be refreshed. Sign in again.":
        "No se pudo actualizar tu sesión. Inicia sesión de nuevo.",
    "Cloud accounts are not configured in this build.":
        "Las cuentas en la nube no están configuradas en esta versión.",
    "This account request could not be completed. Check your connection and try again.":
        "No se pudo completar la solicitud de cuenta. Comprueba tu conexión e inténtalo de nuevo.",
    "Your account is ready.": "Tu cuenta está lista.",
    "Check your email for the verification link, then return here and sign in. If the address is already registered, use sign in or reset your password.":
        "Busca el enlace de verificación en tu correo, vuelve aquí e inicia sesión. Si la dirección ya está registrada, inicia sesión o restablece tu contraseña.",
    "Enter your email address first.":
        "Introduce primero tu dirección de correo.",
    "If this email has an account, a password reset link will arrive shortly. Open it on this device.":
        "Si este correo tiene una cuenta, pronto recibirás un enlace para restablecer la contraseña. Ábrelo en este dispositivo.",
    "Enter your account email first.":
        "Introduce primero el correo de tu cuenta.",
    "If verification is needed, a new link will arrive by email.":
        "Si es necesario verificar, recibirás un nuevo enlace por correo.",
    "Use a password with at least 8 characters.":
        "Usa una contraseña de al menos 8 caracteres.",
    "Your password has been updated.": "Tu contraseña se ha actualizado.",
    "Enter your current password to delete this account.":
        "Introduce tu contraseña actual para eliminar esta cuenta.",
    "The account changed. Sign in again before deleting.":
        "La cuenta ha cambiado. Inicia sesión de nuevo antes de eliminarla.",
    "Your account and cloud projects have been deleted.":
        "Tu cuenta y tus proyectos en la nube se han eliminado.",
    "The cloud service URL is invalid.":
        "La URL del servicio en la nube no es válida.",
    "The cloud service requires a secure connection.":
        "El servicio en la nube requiere una conexión segura.",
    "A public client key is required.":
        "Se necesita una clave pública de cliente.",
    "The public client key is invalid.":
        "La clave pública de cliente no es válida.",
    "Cloud sign in could not start. Check this build’s cloud settings and secure storage access.":
        "No se pudo iniciar la sesión en la nube. Comprueba la configuración de esta versión y el acceso al almacenamiento seguro.",
    "This plan changed or this review is already closed. Refresh to review the latest version.":
        "Este plan ha cambiado o la revisión ya está cerrada. Actualiza para revisar la versión más reciente.",
    "This project or review link is unavailable, expired, or revoked.":
        "Este proyecto o enlace de revisión no está disponible, ha caducado o se ha revocado.",
    "Sign in again to continue.": "Inicia sesión de nuevo para continuar.",
    "This change could not be accepted. Review the fields and try again.":
        "No se pudo aceptar este cambio. Revisa los campos e inténtalo de nuevo.",
    "This request was already recorded. Refresh to see the result.":
        "Esta solicitud ya se ha registrado. Actualiza para ver el resultado.",
    "The cloud request could not be completed. Try again.":
        "No se pudo completar la solicitud en la nube. Inténtalo de nuevo.",
    "Verify your email before signing in. Check your inbox for the verification link.":
        "Verifica tu correo antes de iniciar sesión. Busca el enlace de verificación en tu bandeja de entrada.",
    "The email or password is incorrect.":
        "El correo o la contraseña son incorrectos.",
    "Choose a stronger password and try again.":
        "Elige una contraseña más segura e inténtalo de nuevo.",
    "Please wait before requesting another email.":
        "Espera antes de solicitar otro correo.",
    "This email may already have an account. Try signing in.":
        "Es posible que este correo ya tenga una cuenta. Intenta iniciar sesión.",
    "This account request could not be completed. Try again.":
        "No se pudo completar la solicitud de cuenta. Inténtalo de nuevo.",
    "The cloud service could not be reached. Check your connection and try again.":
        "No se pudo conectar con el servicio en la nube. Comprueba tu conexión e inténtalo de nuevo.",
    "Your account could not be deleted. Please try again.":
        "No se pudo eliminar tu cuenta. Inténtalo de nuevo.",
    "Review link copied.": "Enlace de revisión copiado.",
    "Share a review link": "Compartir un enlace de revisión",
    "Anyone with a link can respond. The receipt records a link holder, not a verified person. Copying or sharing a link does not mean it was delivered.":
        "Cualquier persona con el enlace puede responder. El comprobante registra a quien tiene el enlace, no a una persona verificada. Copiar o compartir el enlace no confirma su entrega.",
    "This proposal is closed, out of date, or an example. A new link cannot be created.":
        "Esta propuesta está cerrada, ya no está actualizada o es un ejemplo. No se puede crear un nuevo enlace.",
    "A public web address is needed before links can be shared from this build.":
        "Se necesita una dirección web pública para compartir enlaces desde esta versión.",
    "Items this reviewer can see": "Elementos que esta persona puede ver",
    "Source text is included when every changed item is selected. Partial reviews omit source text outside their scope.":
        "El texto fuente se incluye cuando se seleccionan todos los elementos modificados. Las revisiones parciales omiten el texto fuente ajeno a su alcance.",
    "Link expires after": "El enlace caduca en",
    "1 hour": "1 hora",
    "1 day": "1 día",
    "7 days": "7 días",
    "Create private review link": "Crear enlace privado de revisión",
    "Expires": "Caduca",
    "Copy link": "Copiar enlace",
    "Share link": "Compartir enlace",
    "Links for this version": "Enlaces de esta versión",
    "No review links yet.": "Aún no hay enlaces de revisión.",
    "Revoked": "Revocado",
    "Expired": "Caducado",
    "Response recorded": "Respuesta registrada",
    "Awaiting response": "Esperando respuesta",
    "Revoke": "Revocar",
    "Refresh links": "Actualizar enlaces",
    "The local recording index is full. Export recordings before adding more.":
        "El índice local de grabaciones está lleno. Exporta grabaciones antes de añadir más.",
    "The local recording index could not be accessed on this device.":
        "No se pudo acceder al índice local de grabaciones en este dispositivo.",
    "The local recording index could not be saved on this device.":
        "No se pudo guardar el índice local de grabaciones en este dispositivo.",
    "The local recording index could not be cleared on this device.":
        "No se pudo borrar el índice local de grabaciones en este dispositivo.",
    "subscription": "Suscripción",
    "subscriptionBody":
        "Tu espacio gratuito sigue disponible. Los planes de la tienda aparecerán aquí cuando estén configurados.",
    "subscriptionFreeLimits":
        "Gratis: 3 proyectos y hasta 5 solicitudes de IA al día.",
    "subscriptionProLimits":
        "Pro: 100 proyectos y hasta 20 solicitudes de IA al día.",
    "subscriptionAllowanceNote":
        "Las funciones de IA requieren disponibilidad del proveedor y comparten un presupuesto diario del servicio.",
    "subscriptionLimitReached": "Has alcanzado el límite de tu plan actual.",
    "remindersTitle": "Recordatorios de fechas límite",
    "remindersIntro":
        "Recordatorios opcionales para el espacio que estás viendo. Al activarlos, el dispositivo te pedirá permiso para mostrar notificaciones.",
    "remindersToggle": "Recordarme las próximas fechas límite",
    "remindersTiming":
        "Recall programa hasta 32 recordatorios para los elementos sin terminar del plan actual, alrededor de las 9:00 en la zona horaria del dispositivo el día anterior a una fecha límite, o el propio día si todavía no son las 9:00. Las fechas no implican una hora de entrega acordada.",
    "remindersPrivacy":
        "Las notificaciones usan texto genérico. Nunca incluyen nombres de proyectos, personas, textos de fuentes ni precios.",
    "remindersDelivery":
        "La entrega depende de los ajustes de notificación del dispositivo y de las restricciones de batería. Son recordatorios locales, no notificaciones push del servidor.",
    "remindersScheduleCount": "Programados en este dispositivo: {count}",
    "remindersZone": "Zona horaria del dispositivo: {zone}",
    "remindersLastSync": "Última comprobación: {date}",
    "remindersRefresh": "Actualizar recordatorios",
    "remindersSettings": "Abrir ajustes de notificaciones",
    "remindersOff": "Los recordatorios están desactivados.",
    "remindersUnavailable":
        "Los recordatorios locales de fechas límite están disponibles en Android e iOS.",
    "remindersPermission":
        "El permiso de notificaciones está bloqueado. Activa las notificaciones en los ajustes del dispositivo y vuelve aquí.",
    "remindersZoneFailed":
        "No se pudo determinar la zona horaria del dispositivo. No hay recordatorios programados.",
    "remindersReady": "Los recordatorios de este espacio están actualizados.",
    "remindersEmpty": "Ninguna próxima fecha límite necesita un recordatorio.",
    "remindersFailed":
        "No se pudieron actualizar los recordatorios. Abre Recall para volver a intentarlo.",
    "remindersSyncing": "Actualizando recordatorios locales…",
    "remindersNoWorkspace": "Abre un espacio para preparar sus recordatorios.",
    "deadlineNotificationTitle": "Recall",
    "deadlineNotificationBody":
        "Se acerca una fecha límite de un proyecto. Abre Recall para revisar tu plan.",
    "subscriptionActive": "Pro verificado",
    "subscriptionInactive": "Espacio gratuito",
    "subscriptionUnverified": "Suscripción sin verificar",
    "subscriptionUnavailable":
        "Las suscripciones de la tienda no están disponibles en este dispositivo o no están configuradas.",
    "subscriptionSignIn": "Inicia sesión para ver tu suscripción.",
    "subscriptionRestore": "Restaurar compras",
    "subscriptionRefresh": "Verificar suscripción",
    "subscriptionManage": "Gestionar en la tienda",
    "subscriptionCancelled":
        "Compra cancelada. No se ha modificado ninguna suscripción.",
    "subscriptionPending":
        "Tu compra espera la aprobación de la tienda. Verifica de nuevo cuando se apruebe.",
    "subscriptionVerifyFailed":
        "Es posible que la compra se haya completado, pero la verificación del servidor no está disponible. Restaura o verifica de nuevo antes de volver a comprar.",
    "subscriptionError":
        "La tienda no pudo completar esta solicitud. Inténtalo de nuevo.",
    "subscriptionNoPlans":
        "No hay planes de la tienda disponibles en este momento.",
    "subscriptionBuy": "Continuar con este plan",
    "subscriptionRenewal":
        "Las suscripciones se renuevan automáticamente salvo que se cancelen en los ajustes de la tienda. La tienda muestra el período de facturación, las condiciones de prueba y el precio total antes de comprar.",
    "subscriptionAccountChanged":
        "Tu cuenta ha cambiado. Vuelve a abrir esta página para la cuenta actual.",
    "subscriptionStoreBusy": "Hay otra acción de compra en curso.",
    "subscriptionStale":
        "Es necesario actualizar la verificación de la suscripción.",
    "subscriptionTerms":
        "Revisa las condiciones de la tienda antes de confirmar el pago.",
    "licenses": "Licencias de código abierto",
    "deleteProject": "Eliminar proyecto",
    "deleteProjectBody":
        "¿Eliminar este proyecto y sus enlaces de revisión? Primero exporta lo que necesites. También se eliminarán las grabaciones disponibles en este dispositivo.",
    "shareReview": "Compartir un enlace de revisión",
    "cloudWorkspaceNote":
        "Espacio en la nube. Las fuentes escritas y los planes se guardan en tu cuenta. Las grabaciones permanecen en este dispositivo.",
    "Some local recordings could not be removed. Try again.":
        "No se pudieron eliminar algunas grabaciones locales. Inténtalo de nuevo.",
    "subscriptionPeriodDays": "Período de facturación (días): {count}",
    "subscriptionPeriodWeeks": "Período de facturación (semanas): {count}",
    "subscriptionPeriodMonths": "Período de facturación (meses): {count}",
    "subscriptionPeriodYears": "Período de facturación (años): {count}",
    "categoryCreative": "Creativo",
    "categoryServices": "Servicios",
    "categorySoftware": "Software",
    "categoryConsulting": "Consultoría",
    "categoryEvents": "Eventos",
    "categoryOther": "Otro",
    "cloudReviewIdentity":
        "Las respuestas se registraron mediante enlaces privados de revisión. Tener el enlace no verifica la identidad de quien responde.",
    "aiAnalyzeAction": "Obtener sugerencias de IA",
    "aiTranscribeAction": "Transcribir esta grabación",
    "aiAccountOnly":
        "Las acciones opcionales de IA requieren un espacio de cuenta con sesión iniciada y un servicio configurado. La revisión manual siempre está disponible.",
    "aiAnalyzeConsentTitle": "¿Enviar esta fuente para analizarla con IA?",
    "aiAnalyzeConsentBody":
        "Envía la fuente escrita de abajo y el elemento seleccionado del plan actual a OpenAI mediante el servicio de tu cuenta. Pueden incluir información privada de clientes. OpenAI la procesa según sus políticas de datos de la API. Las sugerencias son borradores; no se cambian ni se guardan valores del plan.",
    "aiSelectedCurrentItem": "Elemento seleccionado del plan actual",
    "aiSendText": "Enviar este texto",
    "aiTranscribeConsentTitle": "¿Enviar toda la grabación para transcribirla?",
    "aiTranscribeConsentBody":
        "Envía toda esta grabación a OpenAI mediante el servicio de tu cuenta. Puede incluir voces e información privada. Confirma que tienes permiso para compartirla. OpenAI la procesa según sus políticas de datos de la API. Podrás revisar y editar la transcripción antes de decidir si la añades. El audio no se sube automáticamente.",
    "aiSendAudio": "Enviar esta grabación",
    "aiTranscriptReviewTitle": "Revisar la transcripción automática",
    "aiTranscriptReviewNote":
        "Esta transcripción automática puede interpretar mal palabras, nombres, importes o fechas. Revísala y corrígela antes de añadirla. Se guarda como tu recuerdo, no como una cita original autenticada.",
    "aiAppendTranscript": "Añadir transcripción revisada",
    "aiTranscriptAdded":
        "Se ha añadido una transcripción automática revisada a tu fuente escrita. La grabación permanece en este dispositivo.",
    "aiDraftTitle": "Sugerencias para tu revisión",
    "aiDraftNote":
        "No se ha aplicado nada. Compara la fuente con el plan actual y edita tú los valores propuestos abajo. Comprueba cada importe, moneda, fecha y condición antes de confirmar tu revisión.",
    "aiNoSuggestions":
        "No se han recibido sugerencias. Continúa con la revisión manual.",
    "aiSuggestedText": "Texto sugerido para comprobar",
    "aiSourceQuote": "Cita de la fuente que lo respalda",
    "aiQuestion": "Necesita aclaración",
    "aiIntentRequest": "Posible solicitud de cambio",
    "aiIntentTentative": "Idea provisional",
    "aiIntentWithdrawal": "Posible retirada",
    "aiIntentNoChange": "No se ha identificado ningún cambio",
    "aiIntentUnclear": "El significado no está claro",
    "aiWorking": "Procesando tu solicitud… Tu plan sigue igual.",
    "aiSignIn": "Inicia sesión en el espacio de tu cuenta antes de usar la IA.",
    "aiAccountChanged":
        "Tu cuenta ha cambiado. No se ha añadido nada. Vuelve a abrir este proyecto en la cuenta actual.",
    "aiConsentRequired":
        "Aprueba esta acción concreta de IA antes de enviar contenido.",
    "aiSourceLimit":
        "El análisis de IA necesita una fuente con texto de un máximo de 12.000 caracteres y 32 KB en UTF-8. Tu fuente actual sigue igual.",
    "aiItemLimit":
        "Este elemento del plan es demasiado largo o no está disponible para analizarlo con IA. Continúa con la revisión manual.",
    "aiAudioLimit":
        "Elige una grabación que no esté vacía y no supere 20 MiB. Tu fuente escrita sigue igual.",
    "aiAudioFormat":
        "Este formato no está disponible para la transcripción. Añade una fuente escrita.",
    "aiInvalidResult":
        "No se pudo comprobar la respuesta de la IA de forma segura. Tu fuente y tu plan siguen igual.",
    "aiAllowance":
        "Se ha alcanzado el límite diario de IA o el presupuesto compartido del servicio. Continúa manualmente o inténtalo mañana.",
    "aiUnavailable":
        "El servicio de IA no está configurado, no está disponible o ha alcanzado un límite de gasto. Continúa manualmente.",
    "aiTimeout":
        "La solicitud de IA agotó el tiempo de espera. No se ha reintentado automáticamente. Tu fuente y tu plan siguen igual.",
    "aiFailed":
        "No se pudo completar la solicitud de IA. Tu fuente y tus cambios siguen aquí. No se ha reintentado automáticamente.",
    "Draft suggestions require human review. Every amount, currency and date must be checked.":
        "Las sugerencias necesitan revisión humana. Hay que comprobar cada importe, moneda y fecha.",
    "Verbatim evidence does not prove the intended meaning, speaker identity or agreement.":
        "Una cita literal no prueba el significado previsto, la identidad de quien habla ni su acuerdo.",
    "Unsupported source evidence was discarded.":
        "Se ha descartado una cita no respaldada por la fuente.",
    "A value without verbatim supporting evidence was discarded.":
        "Se ha descartado un valor sin respaldo literal de la fuente.",
  },
  'fr': {
    'today': "Aujourd'hui",
    'projects': 'Projets',
    'sources': 'Sources',
    'addUpdate': 'Ajouter une mise à jour',
    'welcome': 'Un plan clair.\nMême quand il change.',
    'welcomeBody':
        'Gardez le plan actuel, les demandes de modification et les prochaines étapes ensemble.',
    'start': 'Créer votre premier projet',
    'tryExample': "Explorer l'exemple",
    'sample': "Espace d'exemple",
    'sampleNote': 'Projets fictifs. Les réponses sont simulées.',
    'overview': 'Un peu de clarté pour la suite.',
    'review': 'À examiner',
    'waiting': "En attente d'une réponse",
    'dueNext': 'Prochaines échéances',
    'allClear': 'De la place pour avancer.',
    'currentPlan': 'Plan actuel',
    'proposed': 'Modification proposée',
    'confirmed': 'Confirmé',
    'privatePlan': 'Votre plan enregistré',
    'version': 'Version',
    'newProject': 'Nouveau projet',
    'projectTitle': 'Nom du projet',
    'clientName': 'Avec qui travaillez-vous ?',
    'category': 'Type de travail',
    'create': 'Créer le projet',
    'cancel': 'Annuler',
    'save': 'Enregistrer',
    'searchProjects': 'Rechercher un projet',
    'emptyProjects': 'Votre prochain projet commence ici.',
    'emptyProjectsBody': 'Donnez-lui un nom, puis ajoutez votre plan.',
    'emptySources': 'Chaque changement a une origine.',
    'emptySourcesBody':
        "Les sources apparaissent ici, dans leur langue d'origine.",
    'addItem': 'Ajouter au plan',
    'itemTitle': 'Livrable ou engagement',
    'details': 'Détails et conditions',
    'owner': 'Responsable',
    'you': 'Vous',
    'date': 'Date de livraison',
    'noDate': 'Aucune date convenue',
    'totalFee': 'Prix total',
    'amount': 'Montant',
    'currency': 'Devise',
    'source': 'Source',
    'original': 'Texte original',
    'recollection': 'Votre souvenir',
    'sourceLanguage': 'Langue de la source',
    'sourceHint': 'Collez le message ou décrivez votre souvenir.',
    'newValues': 'Vérifiez les valeurs proposées',
    'current': 'Actuel',
    'new': 'Proposé',
    'reviewSource': 'Voir la source',
    'keepChange': 'Enregistrer la proposition',
    'acceptMine': 'Accepter cette version en mon nom',
    'clientPreview': 'Aperçu client',
    'history': 'Historique',
    'correct': 'Demander une correction',
    'correction': 'Correction demandée',
    'correctionNote': 'Que faut-il modifier ?',
    'sendCorrection': 'Enregistrer la demande',
    'pending': "En attente d'une réponse",
    'myAnswer': 'Votre réponse est attendue',
    'inspect': 'Examiner les changements',
    'sampleConfirm': 'Simuler la confirmation du client',
    'simulation':
        "Exemple uniquement. Aucun message envoyé ni identité vérifiée.",
    'settings': 'Votre espace',
    'language': "Langue de l'interface",
    'privacy': 'Confidentialité et stockage',
    'appearance': "Apparence selon l'appareil",
    'delete': "Supprimer l'espace local",
    'deleteAction': 'Supprimer les données locales',
    'savedLocal': 'Enregistré sur cet appareil',
    'noCloud': 'Espace local · sans synchronisation',
    'markProgress': 'Avancement',
    'open': 'Non commencé',
    'inProgress': 'En cours',
    'delivered': 'Livré',
    'accepted': 'Accepté par vous',
    'newPlan': 'Un endroit pour le plan.',
    'file': 'Importer du texte',
    'paste': 'Coller du texte',
    'record': 'Enregistrer un résumé',
    'stop': "Arrêter l'enregistrement",
    'required': 'Ajoutez une valeur pour continuer.',
    'sourceRequired': 'Ajoutez la source ou votre souvenir.',
    'chooseProject': 'Choisir un projet',
    'chooseItem': 'Quel élément a changé ?',
    'noItems': "Ajoutez d'abord un élément au plan.",
    'resetDemo': "Quitter l'exemple",
    'loading': 'Ouverture de votre espace…',
    'retry': 'Réessayer',
    'error': 'Votre travail demande votre attention',
    'export': 'Exporter votre espace',
    'import': 'Restaurer une exportation',
    'sourceSaved': "Langue d'origine conservée",
    'copy': "Copier l'export",
    'support': 'Informations de version',
    'projectCount': 'Projets actifs',
    'needAnswer': 'Réponses attendues',
    'exportRecording': "Exporter l’enregistrement",
    'recordingExportFailed':
        "L’enregistrement n’a pas pu être exporté. Réessayez.",
    'recordingUnavailable':
        "Cet enregistrement est indisponible. Il a peut-être été déplacé ou restauré sur un autre appareil. Exportez-le depuis l’appareil d’origine.",
    'viewAll': 'Tout voir',
    'close': 'Fermer',
    "privacyBody":
        "Le texte des projets mobiles utilise le stockage sécurisé de l’appareil. Les pièces jointes audio sont des fichiers privés de l’application et ne sont pas chiffrées par ce service. Le stockage web offre des protections différentes. Les projets de compte utilisent le service cloud configuré ; les projets de l’appareil ne sont jamais transférés automatiquement. L’IA facultative envoie uniquement le texte précis ou l’enregistrement entier que vous autorisez explicitement.",
    "supportBody":
        "Recall 0.2. Connectez-vous pour utiliser votre espace cloud et les liens de révision. L’IA facultative et les abonnements de la boutique sont disponibles lorsque leurs services sont configurés. Les rappels facultatifs d’échéances sont disponibles sur Android et iOS avec l’autorisation de notification.",
    "noReview": "Aucune modification ne nécessite votre examen.",
    "noAmount": "Aucun montant enregistré",
    "baselineNote":
        "Il s’agit de votre plan de travail privé. L’enregistrer ne confirme pas l’accord d’une autre personne.",
    "reviewNote":
        "Une demande reste une proposition jusqu’à ce que les personnes requises confirment la même version.",
    "sourceEvidence": "Source et contexte",
    "noSources": "Aucune source jointe.",
    "realSharing":
        "Un aperçu n’envoie pas de demande. Les réponses réelles nécessitent un service de révision connecté.",
    "deleteConfirm": "Supprimer votre espace local ?",
    "deleteBody":
        "Exportez d’abord ce dont vous avez besoin. Cette action est irréversible et ne supprime pas de compte distant.",
    "deliveryNote":
        "L’avancement de la livraison est distinct du plan. L’envoi d’un fichier ne signifie pas que le client l’a accepté ou payé.",
    "newPlanBody":
        "Ajoutez ce qui est déjà connu. Comparez ensuite les demandes de modification à ce plan.",
    "recordNotice":
        "Enregistrez votre propre souvenir, ou une réunion après information et consentement appropriés. L’enregistrement ne transfère pas l’audio. La transcription est une action distincte qui demande votre autorisation.",
    "recorded":
        "Audio enregistré sur cet appareil. Ajoutez une source écrite, ou choisissez séparément la transcription si elle est disponible.",
    "invalidAmount":
        "Utilisez un montant positif ou nul, avec au maximum deux décimales.",
    "exportNote":
        "Cette exportation contient du texte privé de projets et de sources. Les enregistrements ne sont pas inclus ; exportez-les séparément avant de changer d’appareil. Partagez-la uniquement avec les personnes de votre choix.",
    "reviewEmpty": "Aucune modification en attente. Le plan actuel est à jour.",
    "copied": "Copié dans le presse-papiers",
    "sourceTooLong":
        "Limitez cette source à 30 000 caractères. Votre texte existant n’a pas été remplacé.",
    "emptyClipboard": "Le presse-papiers ne contient pas de texte.",
    "clipboardError":
        "L’accès au presse-papiers est indisponible. Vous pouvez saisir la source ci-dessous.",
    "fileTooLarge": "Choisissez un fichier texte de moins de 1 Mo.",
    "fileUnreadable":
        "Ce fichier n’a pas pu être lu. Votre source existante est inchangée.",
    "fileEmpty": "Ce fichier ne contient pas de texte.",
    "fileEncoding":
        "Choisissez un fichier texte UTF-8. Rien dans votre source n’a été remplacé.",
    "fileImportFailed":
        "Le fichier n’a pas pu être importé. Votre source est toujours présente.",
    "beginRecording": "Démarrer l’enregistrement",
    "micDenied":
        "L’accès au microphone n’a pas été autorisé. Vous pouvez écrire votre souvenir.",
    "oneRecording":
        "Supprimez ou téléchargez l’enregistrement actuel avant d’en créer un autre.",
    "audioRemoveFailed":
        "L’enregistrement n’a pas pu être supprimé. Réessayez.",
    "recordUnsupported":
        "Ce navigateur ou cet appareil ne permet pas l’enregistrement. Vous pouvez ajouter du texte.",
    "recordFailed":
        "L’enregistrement n’a pas pu démarrer. Votre source écrite a été conservée.",
    "audioUnavailable":
        "Aucun enregistrement n’a été obtenu. Votre source écrite est inchangée.",
    "webAudioSession":
        "L’enregistrement est disponible uniquement dans cette session du navigateur. Téléchargez-le avant de quitter.",
    "stopFailed":
        "L’enregistrement n’a pas pu être sauvegardé. Votre source écrite est inchangée.",
    "downloadAudio": "Enregistrer une copie de l’audio",
    "audioCopySaved": "Copie de l’enregistrement sauvegardée.",
    "audioSaveFailed":
        "La copie de l’enregistrement n’a pas pu être sauvegardée. L’enregistrement actuel est inchangé.",
    "unsupportedCurrency":
        "Cet élément utilise une devise que cet éditeur ne prend pas encore en charge. Son montant et sa devise ont été conservés.",
    "reviewValuesFirst":
        "Vérifiez les valeurs et cochez la confirmation ci-dessous.",
    "noChangedValues":
        "Modifiez au moins une valeur du plan avant d’enregistrer une proposition.",
    "proposalSaved": "Proposition enregistrée. Le plan actuel n’a pas changé.",
    "saveFailed":
        "L’enregistrement a échoué. Votre source et vos modifications sont toujours présentes.",
    "back": "Retour",
    "manualReview":
        "Ajoutez la source, puis vérifiez les nouvelles valeurs du plan. Les actions d’IA facultatives ne démarrent que si vous les choisissez.",
    "recordingNow": "Enregistrement en cours",
    "removeAudio": "Supprimer l’enregistrement",
    "importedFile": "Importé",
    "clearDate": "Supprimer la date proposée",
    "totalAmountNote":
        "Montant total de cet élément, pas un supplément. Aucun séparateur de milliers.",
    "reviewedValues": "J’ai vérifié la source, les valeurs et les conditions.",
    "sharedTextTitle": "Texte partagé avec Recall",
    "sharedTextBody":
        "Choisissez un projet pour examiner ce texte. Rien n’est enregistré ni envoyé avant l’enregistrement de la modification proposée.",
    "sharedTextReview": "Examiner le texte partagé",
    "sharedTextDiscard": "Ignorer le texte partagé",
    "sharedTextTooLarge":
        "Ce texte dépasse la limite de réception de 1 Mio. Partagez une sélection plus courte.",
    "sharedTextUnsupported":
        "Recall reçoit le texte brut et les liens partagés sous forme de texte. Les fichiers joints et les URI de contenu ne sont pas pris en charge ici.",
    "sharedTextEmpty": "Ce partage ne contient aucun texte.",
    "sharedTextInvalid":
        "Ce partage n’a pas pu être lu. Réessayez avec du texte brut.",
    "sharedTextQueueFull":
        "Certains partages n’ont pas pu être conservés. Examinez ou ignorez les textes en attente, puis partagez à nouveau ces messages.",
    "sharePlatformNote":
        "La réception de texte partagé est disponible sur Android. Cette version n’inclut pas d’extension de partage iOS.",
    "interfaceLanguageNote":
        "Choisissez l’anglais, l’espagnol ou le français pour l’interface. Les sources conservent leur langue d’origine. Certaines erreurs de service et certains exemples peuvent apparaître en anglais.",
    "openSourceLicenses": "Licences des logiciels libres",
    "workspaceExportTitle": "Exportation de l’espace Recall",
    "exportTooLarge": "Choisissez une exportation de moins de 1 Mo.",
    "restoreWarning":
        "La restauration remplace l’espace local. Exportez d’abord votre travail actuel.",
    "planComparisonLabel":
        "Deux versions d’un plan avec une modification clairement indiquée",
    "accountTitle": "Votre compte",
    "accountDeleteTitle": "Supprimer votre compte ?",
    "accountDeleteBody":
        "Cette action supprime définitivement votre compte, vos projets cloud et vos liens de révision. Votre espace distinct sur l’appareil reste sur cet appareil. La suppression du compte n’annule pas les abonnements App Store ou Google Play ; gérez-les ou résiliez-les dans la boutique.",
    "accountCurrentPassword": "Mot de passe actuel",
    "accountKeep": "Conserver le compte",
    "accountDeletePermanently": "Supprimer définitivement",
    "accountNewPasswordHeading": "Choisissez un nouveau mot de passe.",
    "accountSharedHeading": "Un espace partagé pour vos plans.",
    "accountWelcomeHeading": "Gardez la prochaine version au même endroit.",
    "accountSignedInBody":
        "Votre espace de compte stocke les projets cloud et permet de vrais liens de révision. Les projets de l’appareil restent distincts.",
    "accountSignInBody":
        "Connectez-vous pour créer des projets cloud et inviter des personnes à examiner une modification précise. Les projets de votre appareil ne sont jamais transférés automatiquement.",
    "accountUnavailable": "Les comptes cloud sont indisponibles",
    "accountNotConfigured":
        "Aucun service cloud n’est configuré dans cette version. Vous pouvez continuer à utiliser l’espace de l’appareil.",
    "accountEmailVerified": "Adresse e-mail vérifiée",
    "accountEmailUnverified": "Vérification de l’adresse e-mail requise",
    "accountCheckInbox":
        "Consultez votre boîte de réception avant d’utiliser les projets cloud.",
    "accountResendVerification": "Renvoyer l’e-mail de vérification",
    "accountVerifiedAction": "J’ai vérifié mon adresse e-mail",
    "accountOpenWorkspace": "Ouvrir l’espace du compte",
    "accountSendReset": "Envoyer un e-mail de réinitialisation",
    "accountSignOut": "Se déconnecter",
    "accountEmail": "Adresse e-mail",
    "accountInvalidEmail": "Saisissez une adresse e-mail valide.",
    "accountNewPassword": "Nouveau mot de passe",
    "accountPassword": "Mot de passe",
    "accountHidePassword": "Masquer le mot de passe",
    "accountShowPassword": "Afficher le mot de passe",
    "accountPasswordRequired": "Saisissez votre mot de passe.",
    "accountPasswordLength": "Utilisez au moins 8 caractères.",
    "accountUpdatePassword": "Mettre à jour le mot de passe",
    "accountCreate": "Créer un compte",
    "accountSignIn": "Se connecter",
    "accountHaveAccount": "Vous avez déjà un compte ? Connectez-vous",
    "accountCreatePrompt": "Nouveau sur Recall ? Créez un compte",
    "accountForgotPassword":
        "Mot de passe oublié ? Envoyer un e-mail de réinitialisation",
    "accountDeleteAction": "Supprimer le compte et les données cloud",
    "accountVerificationPending": "Vérification en attente pour {email}",
    "accountUseDevice": "Utiliser l’espace de l’appareil",
    "publicReviewLoadFailed":
        "Cette révision n’a pas pu être ouverte. Vérifiez votre connexion ou demandez un nouveau lien.",
    "publicReviewCorrectionRequired":
        "Décrivez ce qui doit être corrigé avant d’envoyer.",
    "publicReviewResponseFailed":
        "Votre réponse n’a pas pu être confirmée. Réessayez la même réponse pour vérifier sans risque de doublon.",
    "publicReviewTitle": "Recall · Examiner une modification",
    "publicReviewLoading": "Ouverture de cette révision précise…",
    "publicReviewUnavailable": "Cette révision est indisponible.",
    "publicReviewUnavailableBody":
        "Le lien a peut-être expiré ou été révoqué. Demandez un nouveau lien de révision au responsable du projet.",
    "publicReviewFor": "Une révision pour {name}",
    "publicReviewIdentityNote":
        "Toute personne disposant de ce lien privé peut répondre. Recall enregistre la réponse d’un détenteur du lien sans vérifier son identité. Partagez ce lien uniquement avec le destinataire prévu.",
    "publicReviewChanges": "Les modifications proposées",
    "publicReviewCompare":
        "Comparez le plan actuel à la version proposée ci-dessous.",
    "publicReviewNoChanges":
        "Aucune modification visible des éléments ne figure dans cette révision.",
    "publicReviewSourceHeading": "Source incluse dans cette proposition",
    "publicReviewNoSource": "Ce lien n’inclut aucun texte source.",
    "publicReviewOriginal": "Texte original collé · {language}",
    "publicReviewRecollection": "Souvenir personnel · {language}",
    "publicReviewOriginalNote":
        "Fourni par le responsable du projet. Recall n’a pas authentifié la conversation d’origine.",
    "publicReviewRecollectionNote":
        "Il s’agit du souvenir d’une personne et non d’une citation vérifiée.",
    "publicReviewSourceOmitted":
        "Certains textes sources dépassent le périmètre de ce lien et ont été omis.",
    "publicReviewStale": "Cette proposition n’est plus à jour.",
    "publicReviewClosed": "Cette révision est close.",
    "publicReviewClosedBody":
        "Aucune réponse ne peut être ajoutée ici. Demandez au responsable du projet un lien vers la dernière proposition.",
    "publicReviewResponse": "Votre réponse",
    "publicReviewResponseNote":
        "La confirmation s’applique à cette version proposée précise. Demander une correction ou refuser empêche cette proposition de devenir le plan actuel.",
    "publicReviewNote": "Une note ou une correction",
    "publicReviewNoteHint": "Obligatoire pour une demande de correction",
    "publicReviewAcknowledgement":
        "J’ai examiné les modifications et je comprends que ma réponse est enregistrée en tant que détenteur du lien.",
    "publicReviewConfirm": "Confirmer cette version",
    "publicReviewDecline": "Refuser cette proposition",
    "publicReviewRefresh": "Actualiser l’état de la révision",
    "publicReviewConfirmed": "Confirmation enregistrée.",
    "publicReviewCorrectionRecorded": "Demande de correction enregistrée.",
    "publicReviewDeclined": "Refus enregistré.",
    "publicReviewAlreadyAnswered": "Une réponse est déjà enregistrée.",
    "publicReviewReceiptNote":
        "Ce lien a déjà reçu une réponse. Le responsable du projet peut consulter le reçu du détenteur du lien.",
    "publicReviewReceipt": "Reçu : {receipt}",
    "publicReviewProposedVersion": "Version proposée",
    "publicReviewNoItem": "Aucun élément dans cette version",
    "publicReviewDue": "Échéance : {date}",
    "publicReviewOwner": "Responsable : {name}",
    "publicReviewProjectOwner": "Responsable du projet",
    "publicReviewReviewer": "Destinataire de la révision",
    "Your session could not be refreshed. Sign in again.":
        "Votre session n’a pas pu être actualisée. Reconnectez-vous.",
    "Cloud accounts are not configured in this build.":
        "Les comptes cloud ne sont pas configurés dans cette version.",
    "This account request could not be completed. Check your connection and try again.":
        "Cette demande de compte n’a pas pu aboutir. Vérifiez votre connexion et réessayez.",
    "Your account is ready.": "Votre compte est prêt.",
    "Check your email for the verification link, then return here and sign in. If the address is already registered, use sign in or reset your password.":
        "Consultez votre e-mail pour le lien de vérification, puis revenez vous connecter. Si l’adresse est déjà enregistrée, connectez-vous ou réinitialisez votre mot de passe.",
    "Enter your email address first.":
        "Saisissez d’abord votre adresse e-mail.",
    "If this email has an account, a password reset link will arrive shortly. Open it on this device.":
        "Si cette adresse correspond à un compte, un lien de réinitialisation arrivera bientôt. Ouvrez-le sur cet appareil.",
    "Enter your account email first.":
        "Saisissez d’abord l’adresse e-mail de votre compte.",
    "If verification is needed, a new link will arrive by email.":
        "Si une vérification est nécessaire, un nouveau lien arrivera par e-mail.",
    "Use a password with at least 8 characters.":
        "Utilisez un mot de passe d’au moins 8 caractères.",
    "Your password has been updated.": "Votre mot de passe a été mis à jour.",
    "Enter your current password to delete this account.":
        "Saisissez votre mot de passe actuel pour supprimer ce compte.",
    "The account changed. Sign in again before deleting.":
        "Le compte a changé. Reconnectez-vous avant de le supprimer.",
    "Your account and cloud projects have been deleted.":
        "Votre compte et vos projets cloud ont été supprimés.",
    "The cloud service URL is invalid.": "L’URL du service cloud est invalide.",
    "The cloud service requires a secure connection.":
        "Le service cloud nécessite une connexion sécurisée.",
    "A public client key is required.": "Une clé client publique est requise.",
    "The public client key is invalid.": "La clé client publique est invalide.",
    "Cloud sign in could not start. Check this build’s cloud settings and secure storage access.":
        "La connexion cloud n’a pas pu démarrer. Vérifiez la configuration cloud de cette version et l’accès au stockage sécurisé.",
    "This plan changed or this review is already closed. Refresh to review the latest version.":
        "Ce plan a changé ou cette révision est déjà close. Actualisez pour examiner la dernière version.",
    "This project or review link is unavailable, expired, or revoked.":
        "Ce projet ou ce lien de révision est indisponible, expiré ou révoqué.",
    "Sign in again to continue.": "Reconnectez-vous pour continuer.",
    "This change could not be accepted. Review the fields and try again.":
        "Cette modification n’a pas pu être acceptée. Vérifiez les champs et réessayez.",
    "This request was already recorded. Refresh to see the result.":
        "Cette demande a déjà été enregistrée. Actualisez pour voir le résultat.",
    "The cloud request could not be completed. Try again.":
        "La demande cloud n’a pas pu aboutir. Réessayez.",
    "Verify your email before signing in. Check your inbox for the verification link.":
        "Vérifiez votre adresse e-mail avant de vous connecter. Consultez votre boîte de réception pour le lien de vérification.",
    "The email or password is incorrect.":
        "L’adresse e-mail ou le mot de passe est incorrect.",
    "Choose a stronger password and try again.":
        "Choisissez un mot de passe plus sûr et réessayez.",
    "Please wait before requesting another email.":
        "Veuillez patienter avant de demander un autre e-mail.",
    "This email may already have an account. Try signing in.":
        "Cette adresse peut déjà correspondre à un compte. Essayez de vous connecter.",
    "This account request could not be completed. Try again.":
        "Cette demande de compte n’a pas pu aboutir. Réessayez.",
    "The cloud service could not be reached. Check your connection and try again.":
        "Le service cloud est injoignable. Vérifiez votre connexion et réessayez.",
    "Your account could not be deleted. Please try again.":
        "Votre compte n’a pas pu être supprimé. Réessayez.",
    "Review link copied.": "Lien de révision copié.",
    "Share a review link": "Partager un lien de révision",
    "Anyone with a link can respond. The receipt records a link holder, not a verified person. Copying or sharing a link does not mean it was delivered.":
        "Toute personne disposant du lien peut répondre. Le reçu identifie un détenteur du lien, pas une personne vérifiée. Copier ou partager un lien ne confirme pas sa livraison.",
    "This proposal is closed, out of date, or an example. A new link cannot be created.":
        "Cette proposition est close, obsolète ou fictive. Aucun nouveau lien ne peut être créé.",
    "A public web address is needed before links can be shared from this build.":
        "Une adresse web publique est nécessaire pour partager des liens depuis cette version.",
    "Items this reviewer can see": "Éléments visibles par ce destinataire",
    "Source text is included when every changed item is selected. Partial reviews omit source text outside their scope.":
        "Le texte source est inclus lorsque tous les éléments modifiés sont sélectionnés. Les révisions partielles omettent le texte source hors de leur périmètre.",
    "Link expires after": "Le lien expire après",
    "1 hour": "1 heure",
    "1 day": "1 jour",
    "7 days": "7 jours",
    "Create private review link": "Créer un lien de révision privé",
    "Expires": "Expire",
    "Copy link": "Copier le lien",
    "Share link": "Partager le lien",
    "Links for this version": "Liens pour cette version",
    "No review links yet.": "Aucun lien de révision pour le moment.",
    "Revoked": "Révoqué",
    "Expired": "Expiré",
    "Response recorded": "Réponse enregistrée",
    "Awaiting response": "En attente d’une réponse",
    "Revoke": "Révoquer",
    "Refresh links": "Actualiser les liens",
    "The local recording index is full. Export recordings before adding more.":
        "L’index local des enregistrements est plein. Exportez des enregistrements avant d’en ajouter.",
    "The local recording index could not be accessed on this device.":
        "L’index local des enregistrements est inaccessible sur cet appareil.",
    "The local recording index could not be saved on this device.":
        "L’index local des enregistrements n’a pas pu être sauvegardé sur cet appareil.",
    "The local recording index could not be cleared on this device.":
        "L’index local des enregistrements n’a pas pu être effacé sur cet appareil.",
    "subscription": "Abonnement",
    "subscriptionBody":
        "Votre espace gratuit reste disponible. Les offres de la boutique apparaîtront ici une fois configurées.",
    "subscriptionFreeLimits":
        "Gratuit : 3 projets et jusqu’à 5 demandes d’IA par jour.",
    "subscriptionProLimits":
        "Pro : 100 projets et jusqu’à 20 demandes d’IA par jour.",
    "subscriptionAllowanceNote":
        "Les fonctions d’IA dépendent de la disponibilité du fournisseur et partagent un budget quotidien du service.",
    "subscriptionLimitReached":
        "La limite de votre offre actuelle est atteinte.",
    "remindersTitle": "Rappels d’échéances",
    "remindersIntro":
        "Des rappels facultatifs pour l’espace que vous consultez. Leur activation demande à votre appareil l’autorisation d’envoyer des notifications.",
    "remindersToggle": "Me rappeler les échéances à venir",
    "remindersTiming":
        "Recall programme jusqu’à 32 rappels pour les éléments inachevés du plan actuel, vers 9 h dans le fuseau horaire de votre appareil la veille d’une échéance, ou le jour même s’il n’est pas encore 9 h. Une date n’implique pas une heure de livraison convenue.",
    "remindersPrivacy":
        "Les notifications utilisent un texte générique. Elles n’incluent jamais les noms de projets, les personnes, les textes sources ni les prix.",
    "remindersDelivery":
        "La réception dépend des réglages de notification de votre appareil et des restrictions de batterie. Il s’agit de rappels locaux, et non de notifications push du serveur.",
    "remindersScheduleCount": "Programmés sur cet appareil : {count}",
    "remindersZone": "Fuseau horaire de l’appareil : {zone}",
    "remindersLastSync": "Dernière vérification : {date}",
    "remindersRefresh": "Actualiser les rappels",
    "remindersSettings": "Ouvrir les réglages de notification",
    "remindersOff": "Les rappels sont désactivés.",
    "remindersUnavailable":
        "Les rappels locaux d’échéances sont disponibles sur Android et iOS.",
    "remindersPermission":
        "L’autorisation de notification est bloquée. Activez les notifications dans les réglages de votre appareil, puis revenez ici.",
    "remindersZoneFailed":
        "Le fuseau horaire de l’appareil n’a pas pu être déterminé. Aucun rappel n’est programmé.",
    "remindersReady": "Les rappels de cet espace sont à jour.",
    "remindersEmpty": "Aucune échéance à venir ne nécessite de rappel.",
    "remindersFailed":
        "Les rappels n’ont pas pu être actualisés. Ouvrez Recall pour réessayer.",
    "remindersSyncing": "Actualisation des rappels locaux…",
    "remindersNoWorkspace": "Ouvrez un espace pour préparer ses rappels.",
    "deadlineNotificationTitle": "Recall",
    "deadlineNotificationBody":
        "Une échéance de projet approche. Ouvrez Recall pour consulter votre plan.",
    "subscriptionActive": "Pro vérifié",
    "subscriptionInactive": "Espace gratuit",
    "subscriptionUnverified": "Abonnement non vérifié",
    "subscriptionUnavailable":
        "Les abonnements en boutique sont indisponibles sur cet appareil ou ne sont pas configurés.",
    "subscriptionSignIn": "Connectez-vous pour consulter votre abonnement.",
    "subscriptionRestore": "Restaurer les achats",
    "subscriptionRefresh": "Vérifier l’abonnement",
    "subscriptionManage": "Gérer dans la boutique",
    "subscriptionCancelled": "Achat annulé. Aucun abonnement n’a été modifié.",
    "subscriptionPending":
        "Votre achat attend l’approbation de la boutique. Vérifiez à nouveau après approbation.",
    "subscriptionVerifyFailed":
        "Votre achat est peut-être terminé, mais la vérification du serveur est indisponible. Restaurez ou vérifiez à nouveau avant de retenter un achat.",
    "subscriptionError":
        "La boutique n’a pas pu traiter cette demande. Réessayez.",
    "subscriptionNoPlans":
        "Aucune offre de la boutique n’est disponible actuellement.",
    "subscriptionBuy": "Continuer avec cette offre",
    "subscriptionRenewal":
        "Les abonnements se renouvellent automatiquement sauf annulation dans les réglages de la boutique. La boutique affiche la période de facturation, les conditions d’essai et le prix total avant l’achat.",
    "subscriptionAccountChanged":
        "Votre compte a changé. Rouvrez cette page pour le compte connecté.",
    "subscriptionStoreBusy": "Une autre action d’achat est encore en cours.",
    "subscriptionStale":
        "La vérification de l’abonnement doit être actualisée.",
    "subscriptionTerms":
        "Consultez les conditions de la boutique avant de confirmer le paiement.",
    "licenses": "Licences des logiciels libres",
    "deleteProject": "Supprimer le projet",
    "deleteProjectBody":
        "Supprimer ce projet et ses liens de révision ? Exportez d’abord ce dont vous avez besoin. Les enregistrements disponibles sur cet appareil seront également supprimés.",
    "shareReview": "Partager un lien de révision",
    "cloudWorkspaceNote":
        "Espace cloud. Les sources écrites et les plans sont enregistrés dans votre compte. Les enregistrements restent sur cet appareil.",
    "Some local recordings could not be removed. Try again.":
        "Certains enregistrements locaux n’ont pas pu être supprimés. Réessayez.",
    "subscriptionPeriodDays": "Période de facturation (jours) : {count}",
    "subscriptionPeriodWeeks": "Période de facturation (semaines) : {count}",
    "subscriptionPeriodMonths": "Période de facturation (mois) : {count}",
    "subscriptionPeriodYears": "Période de facturation (années) : {count}",
    "categoryCreative": "Création",
    "categoryServices": "Services",
    "categorySoftware": "Logiciel",
    "categoryConsulting": "Conseil",
    "categoryEvents": "Événements",
    "categoryOther": "Autre",
    "cloudReviewIdentity":
        "Les réponses ont été enregistrées via des liens de révision privés. La possession du lien ne vérifie pas l’identité de la personne qui répond.",
    "aiAnalyzeAction": "Obtenir des suggestions de l’IA",
    "aiTranscribeAction": "Transcrire cet enregistrement",
    "aiAccountOnly":
        "Les actions d’IA facultatives nécessitent un espace de compte connecté et un service configuré. La révision manuelle reste disponible.",
    "aiAnalyzeConsentTitle": "Envoyer cette source pour analyse par IA ?",
    "aiAnalyzeConsentBody":
        "Envoyez la source écrite ci-dessous et l’élément sélectionné du plan actuel à OpenAI via votre service de compte. Ils peuvent contenir des informations privées de clients. OpenAI les traite selon ses politiques de données de l’API. Les suggestions sont des brouillons ; aucune valeur du plan n’est modifiée ni enregistrée.",
    "aiSelectedCurrentItem": "Élément sélectionné du plan actuel",
    "aiSendText": "Envoyer ce texte",
    "aiTranscribeConsentTitle":
        "Envoyer l’enregistrement entier pour transcription ?",
    "aiTranscribeConsentBody":
        "Envoyez cet enregistrement entier à OpenAI via votre service de compte. Il peut contenir des voix et des informations privées. Confirmez que vous avez l’autorisation de le partager. OpenAI le traite selon ses politiques de données de l’API. Vous examinerez et corrigerez la transcription avant de choisir de l’ajouter. L’audio n’est jamais transféré automatiquement.",
    "aiSendAudio": "Envoyer cet enregistrement",
    "aiTranscriptReviewTitle": "Examiner la transcription automatique",
    "aiTranscriptReviewNote":
        "Cette transcription automatique peut mal interpréter des mots, des noms, des montants ou des dates. Vérifiez-la et corrigez-la avant de l’ajouter. Elle est enregistrée comme votre souvenir, pas comme une citation originale authentifiée.",
    "aiAppendTranscript": "Ajouter la transcription vérifiée",
    "aiTranscriptAdded":
        "Une transcription automatique vérifiée a été ajoutée à votre source écrite. L’enregistrement reste sur cet appareil.",
    "aiDraftTitle": "Suggestions à examiner",
    "aiDraftNote":
        "Rien n’a été appliqué. Comparez la source au plan actuel, puis modifiez vous-même les valeurs proposées ci-dessous. Vérifiez chaque montant, devise, date et condition avant de confirmer votre examen.",
    "aiNoSuggestions":
        "Aucune suggestion n’a été reçue. Poursuivez la révision manuelle.",
    "aiSuggestedText": "Texte suggéré à vérifier",
    "aiSourceQuote": "Extrait de la source à l’appui",
    "aiQuestion": "Clarification nécessaire",
    "aiIntentRequest": "Demande de modification possible",
    "aiIntentTentative": "Idée provisoire",
    "aiIntentWithdrawal": "Retrait possible",
    "aiIntentNoChange": "Aucune modification identifiée",
    "aiIntentUnclear": "Le sens est incertain",
    "aiWorking": "Traitement de votre demande… Votre plan est inchangé.",
    "aiSignIn":
        "Connectez-vous à votre espace de compte avant d’utiliser l’IA.",
    "aiAccountChanged":
        "Votre compte a changé. Rien n’a été ajouté. Rouvrez ce projet pour le compte connecté.",
    "aiConsentRequired":
        "Autorisez cette action d’IA précise avant d’envoyer du contenu.",
    "aiSourceLimit":
        "L’analyse par IA nécessite une source non vide de 12 000 caractères et 32 Ko de texte UTF-8 au maximum. Votre source existante est inchangée.",
    "aiItemLimit":
        "Cet élément du plan est trop long ou indisponible pour l’analyse par IA. Poursuivez la révision manuelle.",
    "aiAudioLimit":
        "Choisissez un enregistrement non vide de 20 Mio au maximum. Votre source écrite est inchangée.",
    "aiAudioFormat":
        "Ce format n’est pas disponible pour la transcription. Ajoutez une source écrite.",
    "aiInvalidResult":
        "La réponse de l’IA n’a pas pu être vérifiée correctement. Votre source et votre plan sont inchangés.",
    "aiAllowance":
        "La limite quotidienne d’IA ou le budget partagé du service est atteint. Continuez manuellement ou réessayez demain.",
    "aiUnavailable":
        "Le service d’IA n’est pas configuré, est indisponible ou a atteint une limite de dépenses. Continuez manuellement.",
    "aiTimeout":
        "La demande d’IA a expiré. Aucune nouvelle tentative automatique n’a eu lieu. Votre source et votre plan sont inchangés.",
    "aiFailed":
        "La demande d’IA n’a pas pu aboutir. Votre source et vos modifications sont toujours présentes. Aucune nouvelle tentative automatique n’a eu lieu.",
    "Draft suggestions require human review. Every amount, currency and date must be checked.":
        "Les suggestions nécessitent un examen humain. Chaque montant, devise et date doit être vérifié.",
    "Verbatim evidence does not prove the intended meaning, speaker identity or agreement.":
        "Une citation exacte ne prouve ni le sens voulu, ni l’identité de la personne, ni son accord.",
    "Unsupported source evidence was discarded.":
        "Un extrait non étayé par la source a été écarté.",
    "A value without verbatim supporting evidence was discarded.":
        "Une valeur sans extrait exact à l’appui a été écartée.",
  },
};
