typedef RefreshRequestDecision = ({bool shouldQueuePending, bool shouldRunNow});

bool isSessionEligible({
  required bool isAuthenticated,
  required String? authenticatedUserId,
  required String expectedUserId,
}) {
  return isAuthenticated && authenticatedUserId == expectedUserId;
}

bool isSelectionActive(Set<String> selectedGroupIds) {
  return selectedGroupIds.isNotEmpty;
}

bool isLoopActive({
  required bool isEnabled,
  required bool sessionEligible,
  required bool selectionActive,
}) {
  return isEnabled && sessionEligible && selectionActive;
}

bool becameActive(bool previousActive, bool nextActive) {
  return !previousActive && nextActive;
}

bool becameInactive(bool previousActive, bool nextActive) {
  return previousActive && !nextActive;
}

RefreshRequestDecision resolveRefreshRequestDecision({
  required bool isInFlight,
}) {
  return (shouldQueuePending: isInFlight, shouldRunNow: !isInFlight);
}
