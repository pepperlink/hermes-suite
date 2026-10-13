from .provider import DonsetchWebSearchProvider


def register(ctx) -> None:
    ctx.register_web_search_provider(DonsetchWebSearchProvider())
