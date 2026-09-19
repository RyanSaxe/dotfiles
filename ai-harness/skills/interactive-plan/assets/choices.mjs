export function choiceText(choice) {
  if (choice.kind !== "multiple") return choice.valueLabel ?? choice.value;
  if (
    !Array.isArray(choice.options) ||
    !choice.options.every(
      (option) =>
        option &&
        typeof option.value === "string" &&
        typeof option.label === "string" &&
        typeof option.checked === "boolean",
    )
  )
    throw new Error(
      "Checklist options require IDs, labels, and checked states.",
    );
  return (
    choice.options
      .filter((option) => option.checked)
      .map((option) => option.label)
      .join(", ") || "None selected"
  );
}
