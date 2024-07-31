use std::{
    marker::PhantomData,
    sync::{Arc, Mutex},
};

// NOTE: this was inspired from
// https://github.com/worker-tools/html-rewriter-wasm/blob/92bafdfa34c809c37036f57cb282184cada3bbc9/src/handlers.rs

pub struct Anchor<'r> {
    poisoned: Arc<Mutex<bool>>,
    lifetime: PhantomData<&'r mut ()>,
}

impl<'r> Anchor<'r> {
    pub fn new(poisoned: Arc<Mutex<bool>>) -> Self {
        Anchor {
            poisoned,
            lifetime: PhantomData,
        }
    }
}

impl Drop for Anchor<'_> {
    fn drop(&mut self) {
        *self.poisoned.lock().unwrap() = true;
    }
}

// NOTE: So far as I understand it, there's no great wya to work between lol_html's lifetimes and FFI.
// To work around that, we create a wrapper that erases all the lifetime information from the inner reference
// and provides an anchor object that keeps track of the lifetime in the runtime.
//
// When anchor goes out of scope, wrapper becomes poisoned and any attempt to get inner
// object results in exception.
#[derive(Clone)]
pub struct NativeRefWrap<R> {
    inner_ptr: *mut R,
    poisoned: Arc<Mutex<bool>>,
}

impl<R> NativeRefWrap<R> {
    pub fn wrap<I>(inner: &mut I) -> (Self, Anchor) {
        let wrap = NativeRefWrap {
            inner_ptr: inner as *mut I as *mut R,
            poisoned: Arc::new(Mutex::new(false)),
        };

        let anchor = Anchor::new(Arc::clone(&wrap.poisoned));

        (wrap, anchor)
    }

    fn assert_not_poisoned(&self) -> Result<(), &'static str> {
        if self.is_poisoned() {
            Err("The object has been freed and can't be used anymore.")
        } else {
            Ok(())
        }
    }

    pub fn is_poisoned(&self) -> bool {
        *self.poisoned.lock().unwrap()
    }

    pub fn get(&self) -> Result<&R, &'static str> {
        self.assert_not_poisoned()?;

        Ok(unsafe { self.inner_ptr.as_ref() }.unwrap())
    }

    pub fn get_mut(&mut self) -> Result<&mut R, &'static str> {
        self.assert_not_poisoned()?;

        Ok(unsafe { self.inner_ptr.as_mut() }.unwrap())
    }
}
