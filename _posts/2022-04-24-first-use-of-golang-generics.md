---
layout: post
title:  "First use of golang generics"
date:   2022-04-24 00:00:00 -0000
categories: posts
tags: golang programming
---

The biggest feature that golang1.18 introduced for me was [generics](https://go.dev/doc/tutorial/generics).
For me who first started programming in Java where we see the likes of `ArrayList<T>` and `HashMap<T,T>`
everywhere, the lack of generics always seemed unnatural.  Luckily for me, it wasn't hard to find a codebase to
test out generics out in the wild.  More concretely, we have a situation where we have a service where we validate
the name given for many locale. For example, an Engilsh name and a (romanized) Chinese name consist of different
components and often ordered differently, which let's assume can be broken down as below.

```golang
type EnglishName struct {
    Family string `json:"family" validate="min=1,max=50"`
	First  string `json:"first" validate="min=1,max=50"`
	Middle string `json:"middle,omitempty" validate="omitempty,min=1,max=50"`
}

type ChineseName struct {
	Family      string `json:"family" validate="min=1,max=50"`
	Given1      string `json:"given1" validate="min=1,max=50"`
	Given2      string `json:"given2,omitempty" validate="omitempty,min=1,max=50"`
	Generation  string `json:"generation,omitempty" validate="omitempty,min=1,max=50"`
	Courtesy    string `json:"courtesy,omitempty" validate="omitempty,min=1,max=50"`
}
```

The nature of having two different struct means that this is the prime candidate for experimentation. First we define
the parent of the subtypes

```golang
type Name interface {
    ChineseName | EnglishName
}
```

Then we can use the `Name` to initialize a wrapper object that contains the ability to validate, which we will
simply use the validator package here to demonstrate.  Then all that's left is how we would like to use the
object `ValidateName[T]`.
```golang
import 	"github.com/go-playground/validator/v10"

type ValidateName[T Name] struct {
    validate *validator.Validate
}

func NewValidateName[T Name](validate *validator.Validate) *ValidateName[T] {
    if validate == nil {
        validate = validator.New()
    }
    return &ValidateName[T]{validate}
}
```

In the simplest case, we can just implement `func (v *ValidateName) Validate() error` which uses the field
`validate` and test against the struct tags as defined.  Even in the more involved case where we want to
deserialize from the wire and perform validation, it is only a dozen lines of code. The magic happens within
for the defined type automatically where the `[T]` in method `Handler` understands the constraint `T = Name`
as per the type definition of `ValidateName`. 


```golang
import "github.com/gorilla/mux"

func (d *ValidateName[T]) Handler(rw http.ResponseWriter, r *http.Request) {
	name := new(T)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(name); err != nil {
		rw.WriteHeader(http.StatusBadRequest)
		return
	}
	if d.validate.Struct(name) != nil {
		rw.WriteHeader(http.StatusBadRequest)
		return
	}
	rw.WriteHeader(http.StatusOK)
}

func main() {
    router := mux.NewRouter()
    router.HandleFunc("/english", NewValidateName[EnglishName](nil).Handler)
    router.HandleFunc("/chinese", NewValidateName[ChineseName](nil).Handler)
}
```

This extensibility allows us not repeat code for different structs; if we need to carry out different
operations for different struct then we can do a reflection via a switch + case and execute the appropriate
functions.

```
switch v := any(name).(type) {
    case *ChineseName: // something
    case *EnglishName: // more things
    default: // whatever
}
```

One downside that I have discovered so far is the restriction on where you can use types, i.e. for parameterization
only.  The issue is that we can define an interface of methods for the "type interface".  So if we want to have
`func (x *Name) Score(y Name) float64 {}` it is not possible because the interface has to be 

```
type Scorer interface {
	Score(any) float64 // Score(Name) float64 not allowed
}
```

for it to be a valid extension for all `Name` type.  Obviously, this is a not really a problem because the receiver
is parameterized and we can always just set the type in the method to `interface{}` in the method like the good
old days. We are losing a bit of self&ndash;documentation in the method signature, but given the improvement in
the quality of life generics brings, we can most definitely accept a few unintuitive behaviour and start relearning
the golang way of working.
