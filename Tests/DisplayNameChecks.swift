import Foundation

@main
struct DisplayNameChecks {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1
        }
        func autofill(_ display: String, _ first: String, _ last: String) -> String {
            ProfileNameFormatter.displayNameAfterNameChange(displayName: display, firstName: first, lastName: last)
        }
        check(autofill("", "Johnny", "") == "Johnny", "first name only")
        check(autofill("", "", "Laroco") == "Laroco", "last name only")
        check(autofill("", "Johnny", "Laroco") == "Johnny Laroco", "both names")
        check(autofill(" \n", " Johnny ", " Laroco\n") == "Johnny Laroco", "blank whitespace autofill and trimmed combination")
        check(autofill("Big Johnny", "Johnny", "Laroco") == "Big Johnny", "custom name preserved")
        check(autofill("Johnny", "John", "Laroco") == "Johnny", "first name edit preserves previous display")
        check(autofill("Johnny Laroco", "John", "Smith") == "Johnny Laroco", "previously generated nonblank name preserved")
        check(autofill(" Big Johnny ", "John", "Smith") == " Big Johnny ", "nonblank text preserved exactly while editing")
        check(autofill("", " \n", "\t") == "", "no names remains blank")
        // Exercise an editing sequence. Display edits/loads assign the field
        // directly, and only a subsequent name-field event invokes autofill.
        var display = autofill("", "Johnny", "")
        display = autofill(display, "Johnny", "Laroco")
        check(display == "Johnny", "last name entry never overwrites nonblank auto value")
        display = "Big Johnny"
        display = autofill(display, "Jonathan", "Laroco")
        check(display == "Big Johnny", "manual edit survives name edit")
        display = ""
        check(display.isEmpty && ProfileNameFormatter.displayNameError(display) == "Display Name is required.", "clearing stays blank and invalid")
        display = autofill(display, "John", "Laroco")
        check(display == "John Laroco", "next name edit can refill after clear")
        for blank in ["", " ", "\t\n", "\u{00a0}", "\u{2003}"] {
            check(ProfileNameFormatter.displayNameError(blank) == "Display Name is required.", "blank validation")
            let normalized = NormalizedProfileInput(firstName: "John", lastName: "Laroco", displayName: blank)
            check(normalized.displayName == nil, "service normalization rejects blank profile/signup display")
            check(EmailVerification.signupError(firstName: "John", lastName: "Laroco", displayName: blank,
                email: "member@example.com", password: "password", confirmation: "password") == "Display Name is required.", "signup blocked before backend")
        }
        let normalized = NormalizedProfileInput(firstName: " John ", lastName: " Laroco\n", displayName: " Big Johnny ")
        check(normalized.firstName == "John" && normalized.lastName == "Laroco" && normalized.displayName == "Big Johnny", "save trims independent name values")
        let metadata = SignupNames(firstName: " John ", lastName: " Laroco ", displayName: " Big Johnny ").metadata
        check(metadata["display_name"] == "Big Johnny" && metadata["first_name"] == "John", "signup metadata preserves custom display")
        for saved in ["Custom on iPhone", "John Laroco", "", " \n"] {
            let repairs = MissingProfileName.repairs(existing: ["first_name": "John", "last_name": "Laroco", "display_name": saved],
                                                    metadata: metadata)
            check(!repairs.contains { $0.column == "display_name" }, "login/relaunch never repairs display from stale metadata")
        }
        let missing = MissingProfileName.repairs(existing: [:], metadata: metadata)
        check(Set(missing.map(\.column)) == ["first_name", "last_name"], "first/last repair retained, no display repair")
        check(ProfileNameFormatter.displayNameError("名字") == nil, "Unicode display supported")
        check(autofill("", " María ", " García López ") == "María García López", "Unicode name combination")
        check(EmailVerification.signupError(firstName: "John", lastName: "Laroco", displayName: "Big Johnny",
            email: "bad", password: "password", confirmation: "password") == "Enter a valid email address.", "email validation preserved")
        check(EmailVerification.signupError(firstName: "John", lastName: "Laroco", displayName: "Big Johnny",
            email: "member@example.com", password: "password", confirmation: "different") == "Passwords do not match.", "password validation preserved")
        print("Passed \(count) display-name autofill, validation, normalization and restoration checks")
    }
}
