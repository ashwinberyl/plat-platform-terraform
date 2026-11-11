output "budgets" {
  value = [aws_budgets_budget.monthly.name, aws_budgets_budget.tagged.name]
}
