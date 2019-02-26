module Main exposing (main)

import Browser
import Dict
import Html exposing (Html, div, text, textarea)
import Html.Attributes exposing (class, style)
import Html.Events exposing (onInput)
import Json.Decode as D
import Parser exposing ((|.), (|=))


main : Platform.Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    String


init : () -> ( Model, Cmd msg )
init () =
    let
        json =
            """
        [
            {
                "description": "The Foos",
                "start": "9:30 AM",
                "end": "11:00 am",
                "location": "Baz Hall"
            },
            {
                "description": "Maria Blumenface",
                "start": " 10:30am",
                "end": "13:00",
                "location": "The Back Alley"
            },
            {
                "description": "Joshua Farenghetti",
                "start": "12:30 pm",
                "end": "5pm",
                "location": "Baz Hall"
            }
        ]
        """
    in
    ( json, Cmd.none )


type alias Event =
    { description : String
    , start : Time
    , end : Time
    , location : String
    }


type alias Time =
    { hour : Int
    , minute : Int
    }


type alias LocationGroup =
    { location : String
    , events : List Event
    }


locationGroups : List Event -> List LocationGroup
locationGroups events =
    let
        addEvent event dict =
            Dict.update event.location (updateGroup event) dict

        updateGroup event maybeGroup =
            Just (event :: Maybe.withDefault [] maybeGroup)

        locationDict =
            List.foldl addEvent Dict.empty events

        startTime locationGroup =
            locationGroup.events
                |> List.map (\e -> minutesFromMidnight e.start)
                |> List.minimum
                |> Maybe.withDefault 0
    in
    locationDict
        |> Dict.toList
        |> List.map (\kv -> { location = Tuple.first kv, events = Tuple.second kv })
        |> List.sortBy startTime


minutesFromMidnight : Time -> Int
minutesFromMidnight time =
    time.hour * 60 + time.minute



-- UPDATE


type Msg
    = SetJson String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        SetJson newValue ->
            ( newValue, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "schedule-visualizer" ]
        [ textarea [ class "json-input", onInput SetJson ] [ text model ]
        , viewSchedule model
        ]


viewSchedule : Model -> Html Msg
viewSchedule model =
    case D.decodeString scheduleDecoder model of
        Ok events ->
            let
                window =
                    windowForEvents events

                timeHeadings =
                    List.range window.startHour window.endHour
                        |> List.map (\hour -> { hour = hour, minute = 0 })
                        |> List.map (viewTimeHeading window)

                viewLocationGroup locationGroup =
                    div [ class "location-group" ]
                        [ div [ class "location-head" ] [ text locationGroup.location ]
                        , div [ class "events" ] (locationGroup.events |> List.map viewEvent)
                        ]

                viewEvent event =
                    div
                        [ class "event"
                        , style "left" (timeLeftPosition window event.start)
                        , style "width" (timeWidth event.start event.end)
                        ]
                        [ text event.description ]
            in
            div [ class "schedule" ]
                [ div [ class "time-headings" ]
                    timeHeadings
                , div [ class "location-groups" ]
                    (locationGroups events |> List.map viewLocationGroup)
                ]

        Err error ->
            div [ class "json-error" ] [ text (D.errorToString error) ]


type alias Window =
    { startHour : Int
    , endHour : Int
    }


windowForEvents : List Event -> Window
windowForEvents events =
    { startHour =
        events
            |> List.map (\e -> e.start.hour)
            |> List.minimum
            |> Maybe.withDefault 0
    , endHour =
        events
            |> List.map
                (\e ->
                    if e.end.minute == 0 then
                        e.end.hour

                    else
                        e.end.hour + 1
                )
            |> List.maximum
            |> Maybe.withDefault 0
    }


viewTimeHeading : Window -> Time -> Html Msg
viewTimeHeading window time =
    div [ class "time-heading", style "left" (timeLeftPosition window time) ]
        [ text (timeToString time) ]


minutesWidth : Int -> String
minutesWidth minutes =
    String.fromFloat (toFloat minutes / 7) ++ "em"


timeWidth : Time -> Time -> String
timeWidth start end =
    minutesWidth (minutesFromMidnight end - minutesFromMidnight start)


timeLeftPosition : Window -> Time -> String
timeLeftPosition window time =
    minutesWidth (minutesFromMidnight time - (window.startHour * 60))


timeToString : Time -> String
timeToString time =
    let
        amPm =
            if time.hour >= 12 then
                "pm"

            else
                "am"

        displayHour =
            if modBy 12 time.hour == 0 then
                "12"

            else
                String.fromInt (modBy 12 time.hour)
    in
    if time.minute == 0 then
        displayHour ++ amPm

    else
        displayHour ++ ":" ++ String.fromInt time.minute ++ amPm



-- DECODERS


scheduleDecoder : D.Decoder (List Event)
scheduleDecoder =
    D.list entryDecoder


entryDecoder : D.Decoder Event
entryDecoder =
    let
        validateEvent event =
            if minutesFromMidnight event.start > minutesFromMidnight event.end then
                D.fail "Event cannot end before it starts"

            else
                D.succeed event
    in
    D.map4 Event
        (D.field "description" D.string)
        (D.field "start" timeDecoder)
        (D.field "end" timeDecoder)
        (D.field "location" D.string)
        |> D.andThen validateEvent


timeDecoder : D.Decoder Time
timeDecoder =
    let
        parseTime timeString =
            case Parser.run timeParser (String.toLower timeString) of
                Ok time ->
                    D.succeed time

                Err _ ->
                    D.fail "Invalid time"
    in
    D.string
        |> D.andThen parseTime


timeParser : Parser.Parser Time
timeParser =
    Parser.succeed timeFromParsedComponents
        |. Parser.spaces
        |= Parser.int
        |= Parser.oneOf
            [ Parser.succeed identity
                |. Parser.symbol ":"
                |= Parser.oneOf
                    [ Parser.succeed identity
                        |. Parser.chompIf (\c -> c == '0')
                        |= Parser.int
                    , Parser.int
                    ]
            , Parser.succeed 0
            ]
        |. Parser.spaces
        |= Parser.oneOf
            [ Parser.keyword "pm" |> Parser.map (\_ -> True)
            , Parser.keyword "am" |> Parser.map (\_ -> False)
            , Parser.succeed False
            ]
        |. Parser.spaces
        |. Parser.end


timeFromParsedComponents : Int -> Int -> Bool -> Time
timeFromParsedComponents hour minute isPm =
    if isPm && hour < 12 then
        { hour = hour + 12, minute = minute }

    else
        { hour = hour, minute = minute }
