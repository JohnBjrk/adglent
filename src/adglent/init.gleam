import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import priv/errors
import priv/prompt
import priv/template
import priv/templates/test_main
import priv/toml
import simplifile

const aoc_toml_template = "
version = {{ version }}
year = \"{{ year }}\"
session = \"{{ session }}\"
showtime = {{ showtime }}
"

pub fn main() {
  let year = prompt.value("Year", "2023", False)
  let session = prompt.value("Session Cookie", "", False)
  let use_showtime = prompt.confirm("Use showtime", False)

  let aoc_toml_file = "aoc.toml"
  let overwrite = case simplifile.create_file(aoc_toml_file) {
    Ok(_) -> True
    Error(simplifile.Eexist) ->
      prompt.confirm("aoc.toml exits - overwrite", False)
    _ -> panic as "Could not create aoc.toml"
  }
  let _ =
    case overwrite {
      True -> {
        template.render(aoc_toml_template, [
          #("version", "2"),
          #("year", year),
          #("session", session),
          #(
            "showtime",
            bool.to_string(use_showtime)
              |> string.lowercase,
          ),
        ])
        |> simplifile.write(to: aoc_toml_file)
        |> errors.map_messages(
          "aoc.toml - written",
          "Error when writing aoc.toml",
        )
      }

      False -> Ok("aoc.toml - skipped")
    }
    |> errors.print_result

  let gleam_toml =
    simplifile.read("gleam.toml")
    |> errors.map_error("Could not read gleam.toml")
    |> errors.print_error
    |> errors.assert_ok

  let name =
    toml.get_string(gleam_toml, ["name"])
    |> errors.map_error("Could not read \"name\" from gleam.toml")
    |> errors.print_error
    |> errors.assert_ok

  let have_showtime_dependency =
    toml.get_string(gleam_toml, ["dependencies", "showtime"])
    |> result.is_ok

  let test_main_file = "test/" <> name <> "_test.gleam"

  case use_showtime {
    True -> {
      template.render(test_main.template, [])
      |> simplifile.write(to: test_main_file)
      |> errors.map_messages(
        "Wrote " <> test_main_file,
        "Could not write to " <> test_main_file,
      )
    }
    False -> Ok("Using existing (gleeunit) " <> test_main_file)
  }
  |> errors.print_result
  |> errors.assert_ok

  case use_showtime, have_showtime_dependency {
    True, False -> {
      gleam_toml
      |> string.split("\n")
      |> list.fold([], fn(lines, line) {
        case line {
          "[dependencies]" -> ["showtime = \"~> 0.2\"", line, ..lines]
          _ -> [line, ..lines]
        }
      })
      |> list.reverse
      |> string.join("\n")
      |> simplifile.write(to: "gleam.toml")
      |> errors.map_messages(
        "Wrote " <> "gleam.toml",
        "Could not write to " <> "gleam.toml",
      )
    }
    True, True -> Ok("Skip add of showtime dependency (already present)")
    False, _ -> Ok("Skip add of showtime dependency (not configured)")
  }
  |> errors.print_result
  |> errors.assert_ok

  case simplifile.is_file(".gitignore") {
    Ok(True) -> {
      use gitignore <- result.try(
        simplifile.read(".gitignore")
        |> result.map_error(fn(err) {
          "Could not read .gitignore: " <> string.inspect(err)
        }),
      )
      let aoc_toml_ignored =
        string.split(gitignore, "\n")
        |> list.find(fn(line) { line == "aoc.toml" })
      case aoc_toml_ignored {
        Error(_) -> {
          simplifile.append("\naoc.toml", to: ".gitignore")
          |> errors.map_messages(
            ".gitignore written",
            "Error when writing .gitignore",
          )
        }
        Ok(_) -> Ok(".gitignore - skipped (already configured)")
      }
    }
    Ok(False) | Error(_) -> Error("Could not find .gitignore")
  }
  |> errors.print_result
}
