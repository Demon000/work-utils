from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict

# TODO: add extract arg action
# TODO: enforce error for unknown fields


class FrozenStrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', frozen=True)


class RunWriteConfig(FrozenStrictModel):
    type: Literal['write']
    value: str
    needed_args: tuple[str, ...] | None = None


class RunWriteFromFileConfig(FrozenStrictModel):
    type: Literal['write_from_file']
    value: str
    needed_args: tuple[str, ...] | None = None


class RunSetArgConfig(FrozenStrictModel):
    type: Literal['set_arg']
    name: str
    value: str


class AddLogConfig(FrozenStrictModel):
    type: Literal['add_log_file']
    name: str
    needed_args: tuple[str, ...] | None = None


RunConfig = (
    RunWriteConfig | RunWriteFromFileConfig | RunSetArgConfig | AddLogConfig
)


class BaseMatchConfig(FrozenStrictModel):
    run: Optional[tuple[RunConfig, ...]] = None
    oneshot: Optional[bool] = None
    reset_logs: Optional[bool] = None
    reset_oneshots: Optional[bool] = None


class MatchConfig(BaseMatchConfig):
    type: Literal['match']
    value: str


class RegexMatchConfig(BaseMatchConfig):
    type: Literal['match_regex']
    value: str


ActionConfig = MatchConfig | RegexMatchConfig


class Config(FrozenStrictModel):
    write_char_delay_us: int
    program: tuple[str, ...]
    actions: tuple[ActionConfig, ...]
