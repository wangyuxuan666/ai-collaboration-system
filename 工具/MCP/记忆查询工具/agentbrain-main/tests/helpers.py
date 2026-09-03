def lesson_text(text: str) -> str:
    return (
        f"## 经验教训（可复用）\n{text}\n\n"
        "## 适用场景\n相关任务中需要采用这条经验时。\n\n"
        "## 规避方案\n按经验调整行动并验证结果。"
    )
