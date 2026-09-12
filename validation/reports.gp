package validation

// MergeReports combines independently produced reports without losing either
// diagnostics or an incomplete result. Invalid dominates indeterminate, just
// as Collect does for individual checks.
func MergeReports(reports ...Report)Report{
    merged:=Report{state:Valid()};invalid,incomplete:=false,false
    for _,report:=range reports{
        merged.details=append(merged.details,report.Diagnostics()...)
        if report.Incomplete(){incomplete=true}
        match report.State(){case Invalid():invalid=true;case Indeterminate():incomplete=true;case Valid():}
    }
    merged.incomplete=incomplete;if invalid{merged.state=Invalid()}else if incomplete{merged.state=Indeterminate()};return merged
}
