use std::{cell::Cell, marker::PhantomData, mem, rc::Rc};

// NOTE: My Rust isn't good enough to know what any of this does,
// but it was taken from https://github.com/cloudflare/lol-html/blob/1a1ab2e2bf896f815fe8888ed78ccdf46d7c6b85/js-api/src/lib.rs#LL38

pub struct Anchor<'r> {
    poisoned: Rc<Cell<bool>>,
    lifetime: PhantomData<&'r mut ()>,
}

impl<'r> Anchor<'r> {
    pub fn new(poisoned: Rc<Cell<bool>>) -> Self {
        Anchor {
            poisoned,
            lifetime: PhantomData,
        }
    }
}

impl Drop for Anchor<'_> {
    fn drop(&mut self) {
        self.poisoned.replace(true);
    }
}

// NOTE: wasm_bindgen doesn't allow structures with lifetimes. To workaround that
// we create a wrapper that erases all the lifetime information from the inner reference
// and provides an anchor object that keeps track of the lifetime in the runtime.
//
// When anchor goes out of scope, wrapper becomes poisoned and any attempt to get inner
// object results in exception.
pub struct NativeRefWrap<R> {
    inner_ptr: *mut R,
    poisoned: Rc<Cell<bool>>,
}

impl<R> NativeRefWrap<R> {
    pub fn wrap<I>(inner: &I) -> (Self, Anchor) {
        let wrap = NativeRefWrap {
            inner_ptr: unsafe { mem::transmute(inner) },
            poisoned: Rc::new(Cell::new(false)),
        };

        let anchor = Anchor::new(Rc::clone(&wrap.poisoned));

        (wrap, anchor)
    }

    pub fn wrap_mut<I>(inner: &mut I) -> (Self, Anchor) {
        let wrap = NativeRefWrap {
            inner_ptr: unsafe { mem::transmute(inner) },
            poisoned: Rc::new(Cell::new(false)),
        };

        let anchor = Anchor::new(Rc::clone(&wrap.poisoned));

        (wrap, anchor)
    }

    pub fn get_ref(&self) -> Result<&R, &'static str> {
        self.assert_not_poisoned()?;

        Ok(unsafe { self.inner_ptr.as_ref() }.unwrap())
    }

    pub fn get_mut(&mut self) -> Result<&mut R, &'static str> {
        self.assert_not_poisoned()?;

        Ok(unsafe { self.inner_ptr.as_mut() }.unwrap())
    }

    fn assert_not_poisoned(&self) -> Result<(), &'static str> {
        // FIXME:
        // if self.poisoned.get() {
        //     Err("The object has been freed and can't be used anymore.")
        // } else {
        Ok(())
        // }
    }
}
