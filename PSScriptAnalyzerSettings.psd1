@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # Human-facing CLI status intentionally uses the information/host stream.
        'PSAvoidUsingWriteHost'
    )
}
