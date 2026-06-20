"""Model routing for Claude-compatible requests."""

from __future__ import annotations

from dataclasses import dataclass

from loguru import logger

from config.provider_ids import SUPPORTED_PROVIDER_IDS
from config.settings import Settings

from .gateway_model_ids import decode_gateway_model_id
from .models.anthropic import MessagesRequest, TokenCountRequest


@dataclass(frozen=True, slots=True)
class ResolvedModel:
    original_model: str
    provider_id: str
    provider_model: str
    provider_model_ref: str
    thinking_enabled: bool


@dataclass(frozen=True, slots=True)
class RoutedMessagesRequest:
    request: MessagesRequest
    resolved: ResolvedModel


@dataclass(frozen=True, slots=True)
class RoutedTokenCountRequest:
    request: TokenCountRequest
    resolved: ResolvedModel


class ModelRouter:
    """Resolve incoming Claude model names to configured provider/model pairs."""

    def __init__(self, settings: Settings):
        self._settings = settings

    def resolve(
        self, claude_model_name: str, custom_model_override: str | None = None
    ) -> ResolvedModel:
        model_ref = custom_model_override or claude_model_name
        (
            direct_provider_id,
            direct_provider_model,
            force_thinking_enabled,
        ) = self._direct_provider_model(model_ref)
        if direct_provider_id is not None and direct_provider_model is not None:
            thinking_enabled = (
                force_thinking_enabled
                if force_thinking_enabled is not None
                else self._settings.resolve_thinking(direct_provider_model)
            )
            logger.debug(
                "MODEL DIRECT: '{}' -> provider='{}' model='{}' thinking={}",
                claude_model_name,
                direct_provider_id,
                direct_provider_model,
                thinking_enabled,
            )
            return ResolvedModel(
                original_model=claude_model_name,
                provider_id=direct_provider_id,
                provider_model=direct_provider_model,
                provider_model_ref=model_ref,
                thinking_enabled=thinking_enabled,
            )

        provider_model_ref = self._settings.resolve_model(model_ref)
        thinking_enabled = self._settings.resolve_thinking(model_ref)
        provider_id = Settings.parse_provider_type(provider_model_ref)
        provider_model = Settings.parse_model_name(provider_model_ref)
        if provider_model != claude_model_name:
            logger.debug(
                "MODEL MAPPING: '{}' -> '{}' (provider: {})",
                claude_model_name,
                provider_model,
                provider_id,
            )
        return ResolvedModel(
            original_model=claude_model_name,
            provider_id=provider_id,
            provider_model=provider_model,
            provider_model_ref=provider_model_ref,
            thinking_enabled=thinking_enabled,
        )

    def _direct_provider_model(
        self, model_name: str
    ) -> tuple[str | None, str | None, bool | None]:
        decoded = decode_gateway_model_id(model_name)
        if decoded is not None:
            if decoded.provider_id not in SUPPORTED_PROVIDER_IDS:
                return None, None, None
            return (
                decoded.provider_id,
                decoded.provider_model,
                decoded.force_thinking_enabled,
            )

        provider_id, separator, provider_model = model_name.partition("/")
        if not separator:
            return None, None, None
        if provider_id not in SUPPORTED_PROVIDER_IDS:
            return None, None, None
        if not provider_model:
            return None, None, None
        return provider_id, provider_model, None

    def resolve_messages_request(
        self, request: MessagesRequest, custom_model_override: str | None = None
    ) -> RoutedMessagesRequest:
        """Return an internal routed request context."""
        resolved = self.resolve(request.model, custom_model_override)
        routed = request.model_copy(deep=True)
        routed.model = resolved.provider_model
        return RoutedMessagesRequest(request=routed, resolved=resolved)

    def resolve_token_count_request(
        self, request: TokenCountRequest, custom_model_override: str | None = None
    ) -> RoutedTokenCountRequest:
        """Return an internal token-count request context."""
        resolved = self.resolve(request.model, custom_model_override)
        routed = request.model_copy(
            update={"model": resolved.provider_model}, deep=True
        )
        return RoutedTokenCountRequest(request=routed, resolved=resolved)
